# ---------------------------------------------------------------------------------------------------------------------
# LOCALS
# ---------------------------------------------------------------------------------------------------------------------

locals {
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "${var.project_name}-${var.environment}-rg"
  resource_prefix     = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUPS
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "primary" {
  name     = "${local.resource_group_name}-primary"
  location = var.primary_location
  tags     = merge(local.common_tags, { Region = "Primary" })
}

resource "azurerm_resource_group" "secondary" {
  name     = "${local.resource_group_name}-secondary"
  location = var.secondary_location
  tags     = merge(local.common_tags, { Region = "Secondary" })
}

# ---------------------------------------------------------------------------------------------------------------------
# RANDOM PASSWORD GENERATION
# ---------------------------------------------------------------------------------------------------------------------

resource "random_password" "postgres_password" {
  length  = 32
  special = true
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE CONTAINER REGISTRY (PRIMARY - GEO-REPLICATED)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = replace("${local.resource_prefix}acr", "-", "")
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  sku                 = var.acr_sku
  admin_enabled       = true

  georeplications {
    location = var.secondary_location
    tags     = local.common_tags
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# LOG ANALYTICS WORKSPACE
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "primary" {
  name                = "${local.resource_prefix}-law-primary"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  sku                 = "PerGB2018"
  retention_in_days   = 90

  tags = local.common_tags
}

resource "azurerm_log_analytics_workspace" "secondary" {
  name                = "${local.resource_prefix}-law-secondary"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  sku                 = "PerGB2018"
  retention_in_days   = 90

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# APPLICATION INSIGHTS
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_application_insights" "primary" {
  name                = "${local.resource_prefix}-appi-primary"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  workspace_id        = azurerm_log_analytics_workspace.primary.id
  application_type    = "web"

  tags = local.common_tags
}

resource "azurerm_application_insights" "secondary" {
  name                = "${local.resource_prefix}-appi-secondary"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  workspace_id        = azurerm_log_analytics_workspace.secondary.id
  application_type    = "web"

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTGRESQL FLEXIBLE SERVER (PRIMARY WITH HA)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server" "primary" {
  name                   = "${local.resource_prefix}-psql-primary"
  resource_group_name    = azurerm_resource_group.primary.name
  location               = azurerm_resource_group.primary.location
  version                = var.postgres_version
  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_password.result

  storage_mb = var.postgres_storage_mb
  sku_name   = var.postgres_sku_name

  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = true

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  tags = local.common_tags
}

# PostgreSQL Firewall Rule - Allow Azure Services
resource "azurerm_postgresql_flexible_server_firewall_rule" "primary_allow_azure" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.primary.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "primary" {
  name      = var.postgres_database_name
  server_id = azurerm_postgresql_flexible_server.primary.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Read Replica in Secondary Region
resource "azurerm_postgresql_flexible_server" "secondary" {
  name                   = "${local.resource_prefix}-psql-secondary"
  resource_group_name    = azurerm_resource_group.secondary.name
  location               = azurerm_resource_group.secondary.location
  create_mode            = "Replica"
  source_server_id       = azurerm_postgresql_flexible_server.primary.id
  version                = var.postgres_version

  storage_mb = var.postgres_storage_mb
  sku_name   = var.postgres_sku_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# REDIS CACHE (PRIMARY WITH GEO-REPLICATION)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_redis_cache" "primary" {
  name                = "${local.resource_prefix}-redis-primary"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  capacity            = var.redis_capacity
  family              = var.redis_family
  sku_name            = var.redis_sku_name

  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  redis_configuration {
    enable_authentication = true
  }

  tags = local.common_tags
}

resource "azurerm_redis_cache" "secondary" {
  name                = "${local.resource_prefix}-redis-secondary"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  capacity            = var.redis_capacity
  family              = var.redis_family
  sku_name            = var.redis_sku_name

  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  redis_configuration {
    enable_authentication = true
  }

  tags = local.common_tags
}

# Geo-replication link
resource "azurerm_redis_linked_server" "geo_replication" {
  target_redis_cache_name     = azurerm_redis_cache.secondary.name
  resource_group_name         = azurerm_resource_group.primary.name
  linked_redis_cache_id       = azurerm_redis_cache.secondary.id
  linked_redis_cache_location = azurerm_redis_cache.secondary.location
  redis_cache_name            = azurerm_redis_cache.primary.name
  server_role                 = "Secondary"
}

# ---------------------------------------------------------------------------------------------------------------------
# STORAGE ACCOUNTS (GEO-REDUNDANT)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_storage_account" "primary" {
  name                     = replace("${local.resource_prefix}saprimary", "-", "")
  resource_group_name      = azurerm_resource_group.primary.name
  location                 = azurerm_resource_group.primary.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.common_tags
}

# Blob Containers
resource "azurerm_storage_container" "containers" {
  for_each              = toset(var.blob_containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.primary.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT (PRIMARY)
# ---------------------------------------------------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "primary" {
  name                       = "${local.resource_prefix}-kv-primary"
  resource_group_name        = azurerm_resource_group.primary.name
  location                   = azurerm_resource_group.primary.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "List", "Create", "Delete", "Purge", "Recover"
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = local.common_tags
}

# Key Vault Secrets
resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres_password.result
  key_vault_id = azurerm_key_vault.primary.id
}

resource "azurerm_key_vault_secret" "postgres_connection_string_primary" {
  name  = "postgres-connection-string-primary"
  value = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.primary.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
  key_vault_id = azurerm_key_vault.primary.id
}

resource "azurerm_key_vault_secret" "postgres_connection_string_secondary" {
  name  = "postgres-connection-string-secondary"
  value = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.secondary.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
  key_vault_id = azurerm_key_vault.primary.id
}

resource "azurerm_key_vault_secret" "redis_connection_string_primary" {
  name  = "redis-connection-string-primary"
  value = "${azurerm_redis_cache.primary.hostname}:${azurerm_redis_cache.primary.ssl_port},password=${azurerm_redis_cache.primary.primary_access_key},ssl=True,abortConnect=False"
  key_vault_id = azurerm_key_vault.primary.id
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.primary.primary_connection_string
  key_vault_id = azurerm_key_vault.primary.id
}

resource "azurerm_key_vault_secret" "cudaap_api_key" {
  count        = var.cudaap_api_key != "" ? 1 : 0
  name         = "cudaap-api-key"
  value        = var.cudaap_api_key
  key_vault_id = azurerm_key_vault.primary.id
}

resource "azurerm_key_vault_secret" "smart_search_api_key" {
  count        = var.smart_search_api_key != "" ? 1 : 0
  name         = "smart-search-api-key"
  value        = var.smart_search_api_key
  key_vault_id = azurerm_key_vault.primary.id
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER APPS ENVIRONMENT (PRIMARY)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_container_app_environment" "primary" {
  name                       = "${local.resource_prefix}-cae-primary"
  resource_group_name        = azurerm_resource_group.primary.name
  location                   = azurerm_resource_group.primary.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.primary.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  workload_profile {
    name                  = "Dedicated-D8"
    workload_profile_type = "D8"
    minimum_count         = 2
    maximum_count         = 5
  }

  tags = local.common_tags
}

resource "azurerm_container_app_environment" "secondary" {
  name                       = "${local.resource_prefix}-cae-secondary"
  resource_group_name        = azurerm_resource_group.secondary.name
  location                   = azurerm_resource_group.secondary.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.secondary.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  workload_profile {
    name                  = "Dedicated-D8"
    workload_profile_type = "D8"
    minimum_count         = 2
    maximum_count         = 5
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER APP - FASTAPI APPLICATION (PRIMARY)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_container_app" "primary" {
  name                         = "${local.resource_prefix}-api-primary"
  resource_group_name          = azurerm_resource_group.primary.name
  container_app_environment_id = azurerm_container_app_environment.primary.id
  revision_mode                = "Single"
  workload_profile_name        = "Dedicated-D8"

  template {
    min_replicas = var.container_apps_min_replicas
    max_replicas = var.container_apps_max_replicas

    container {
      name   = "api"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.primary.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
      }

      env {
        name  = "REDIS_URL"
        value = "rediss://:${azurerm_redis_cache.primary.primary_access_key}@${azurerm_redis_cache.primary.hostname}:${azurerm_redis_cache.primary.ssl_port}/0"
      }

      env {
        name  = "STORAGE_CONNECTION_STRING"
        value = azurerm_storage_account.primary.primary_connection_string
      }

      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.primary.name
      }

      env {
        name  = "CUDAAP_API_ENDPOINT"
        value = var.cudaap_api_endpoint
      }

      env {
        name  = "CUDAAP_API_KEY"
        value = var.cudaap_api_key
      }

      env {
        name  = "SMART_SEARCH_API_ENDPOINT"
        value = var.smart_search_api_endpoint
      }

      env {
        name  = "SMART_SEARCH_API_KEY"
        value = var.smart_search_api_key
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.primary.connection_string
      }

      env {
        name  = "MLFLOW_TRACKING_URI"
        value = var.mlflow_tracking_uri != "" ? var.mlflow_tracking_uri : "wasbs://mlflow-artifacts@${azurerm_storage_account.primary.name}.blob.core.windows.net/"
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "REGION"
        value = "primary"
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Container App - Secondary Region
resource "azurerm_container_app" "secondary" {
  name                         = "${local.resource_prefix}-api-secondary"
  resource_group_name          = azurerm_resource_group.secondary.name
  container_app_environment_id = azurerm_container_app_environment.secondary.id
  revision_mode                = "Single"
  workload_profile_name        = "Dedicated-D8"

  template {
    min_replicas = var.container_apps_min_replicas
    max_replicas = var.container_apps_max_replicas

    container {
      name   = "api"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.secondary.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
      }

      env {
        name  = "REDIS_URL"
        value = "rediss://:${azurerm_redis_cache.secondary.primary_access_key}@${azurerm_redis_cache.secondary.hostname}:${azurerm_redis_cache.secondary.ssl_port}/0"
      }

      env {
        name  = "STORAGE_CONNECTION_STRING"
        value = azurerm_storage_account.primary.primary_connection_string
      }

      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.primary.name
      }

      env {
        name  = "CUDAAP_API_ENDPOINT"
        value = var.cudaap_api_endpoint
      }

      env {
        name  = "CUDAAP_API_KEY"
        value = var.cudaap_api_key
      }

      env {
        name  = "SMART_SEARCH_API_ENDPOINT"
        value = var.smart_search_api_endpoint
      }

      env {
        name  = "SMART_SEARCH_API_KEY"
        value = var.smart_search_api_key
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.secondary.connection_string
      }

      env {
        name  = "MLFLOW_TRACKING_URI"
        value = var.mlflow_tracking_uri != "" ? var.mlflow_tracking_uri : "wasbs://mlflow-artifacts@${azurerm_storage_account.primary.name}.blob.core.windows.net/"
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "REGION"
        value = "secondary"
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Grant Container Apps access to Key Vault
resource "azurerm_key_vault_access_policy" "container_app_primary" {
  key_vault_id = azurerm_key_vault.primary.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app.primary.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]
}

resource "azurerm_key_vault_access_policy" "container_app_secondary" {
  key_vault_id = azurerm_key_vault.primary.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app.secondary.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]
}

# Grant Container Apps access to Storage Account
resource "azurerm_role_assignment" "container_app_storage_primary" {
  scope                = azurerm_storage_account.primary.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_app.primary.identity[0].principal_id
}

resource "azurerm_role_assignment" "container_app_storage_secondary" {
  scope                = azurerm_storage_account.primary.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_app.secondary.identity[0].principal_id
}

# ---------------------------------------------------------------------------------------------------------------------
# API MANAGEMENT (MULTI-REGION)
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_api_management" "main" {
  name                = "${local.resource_prefix}-apim"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name

  additional_location {
    location = var.secondary_location
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# API Management API
resource "azurerm_api_management_api" "compliance_api" {
  name                = "compliance-api"
  resource_group_name = azurerm_resource_group.primary.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Marketing Compliance API"
  path                = "api"
  protocols           = ["https"]

  service_url = "https://${azurerm_container_app.primary.ingress[0].fqdn}"
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE FRONT DOOR
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${local.resource_prefix}-fd"
  resource_group_name = azurerm_resource_group.primary.name
  sku_name            = var.front_door_sku

  tags = local.common_tags
}

# Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "${local.resource_prefix}-fd-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  tags = local.common_tags
}

# Front Door Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "api-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }

  health_probe {
    path                = "/health"
    protocol            = "Https"
    interval_in_seconds = 30
    request_type        = "GET"
  }
}

# Front Door Origins
resource "azurerm_cdn_frontdoor_origin" "primary" {
  name                          = "primary-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  host_name                     = azurerm_container_app.primary.ingress[0].fqdn
  http_port                     = 80
  https_port                    = 443
  priority                      = 1
  weight                        = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_origin" "secondary" {
  name                          = "secondary-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  host_name                     = azurerm_container_app.secondary.ingress[0].fqdn
  http_port                     = 80
  https_port                    = 443
  priority                      = 2
  weight                        = 1000
  certificate_name_check_enabled = true
}

# Front Door Route
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [
    azurerm_cdn_frontdoor_origin.primary.id,
    azurerm_cdn_frontdoor_origin.secondary.id
  ]

  supported_protocols = ["Http", "Https"]
  patterns_to_match   = ["/*"]
  forwarding_protocol = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}
