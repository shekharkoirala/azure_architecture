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
      Location    = var.location
    }
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# RANDOM PASSWORD GENERATION
# ---------------------------------------------------------------------------------------------------------------------

resource "random_password" "postgres_password" {
  length  = 32
  special = true
}

# ---------------------------------------------------------------------------------------------------------------------
# AZURE CONTAINER REGISTRY
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = replace("${local.resource_prefix}acr", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = true

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# LOG ANALYTICS WORKSPACE
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-law"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# APPLICATION INSIGHTS
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-appi"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTGRESQL FLEXIBLE SERVER
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${local.resource_prefix}-psql"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = var.postgres_version
  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_password.result

  storage_mb = var.postgres_storage_mb
  sku_name   = var.postgres_sku_name

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = local.common_tags
}

# PostgreSQL Firewall Rule - Allow Azure Services
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.postgres_database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------------------------------------------------------------------------------------------------------------------
# STORAGE ACCOUNT
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                     = replace("${local.resource_prefix}sa", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Blob Containers
resource "azurerm_storage_container" "containers" {
  for_each              = toset(var.blob_containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT
# ---------------------------------------------------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "${local.resource_prefix}-kv"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = local.common_tags
}

# Key Vault Secrets
resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres_password.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "postgres_connection_string" {
  name  = "postgres-connection-string"
  value = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "cudaap_api_key" {
  count        = var.cudaap_api_key != "" ? 1 : 0
  name         = "cudaap-api-key"
  value        = var.cudaap_api_key
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "smart_search_api_key" {
  count        = var.smart_search_api_key != "" ? 1 : 0
  name         = "smart-search-api-key"
  value        = var.smart_search_api_key
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "app_insights_key" {
  name         = "app-insights-instrumentation-key"
  value        = azurerm_application_insights.main.instrumentation_key
  key_vault_id = azurerm_key_vault.main.id
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER APPS ENVIRONMENT
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_container_app_environment" "main" {
  name                       = "${local.resource_prefix}-cae"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER APP - FASTAPI APPLICATION
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_container_app" "api" {
  name                         = "${local.resource_prefix}-api"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

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
        value = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
      }

      env {
        name  = "STORAGE_CONNECTION_STRING"
        value = azurerm_storage_account.main.primary_connection_string
      }

      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.main.name
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
        value = azurerm_application_insights.main.connection_string
      }

      env {
        name  = "MLFLOW_TRACKING_URI"
        value = var.mlflow_tracking_uri != "" ? var.mlflow_tracking_uri : "wasbs://mlflow-artifacts@${azurerm_storage_account.main.name}.blob.core.windows.net/"
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
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

  # Identity for accessing Key Vault
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Grant Container App access to Key Vault
resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app.api.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]
}

# Grant Container App access to Storage Account
resource "azurerm_role_assignment" "container_app_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_app.api.identity[0].principal_id
}
