# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER REGISTRY OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTGRESQL OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "postgres_server_name" {
  description = "Name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgres_server_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# REDIS CACHE OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "redis_name" {
  description = "Name of the Redis Cache"
  value       = azurerm_redis_cache.main.name
}

output "redis_hostname" {
  description = "Hostname of the Redis Cache"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_ssl_port" {
  description = "SSL port of the Redis Cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_key" {
  description = "Primary access key for Redis Cache"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# STORAGE ACCOUNT OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# ---------------------------------------------------------------------------------------------------------------------
# APPLICATION INSIGHTS OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.main.name
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER APP OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "container_app_name" {
  description = "Name of the Container App"
  value       = azurerm_container_app.api.name
}

output "container_app_url" {
  description = "URL of the Container App"
  value       = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

# ---------------------------------------------------------------------------------------------------------------------
# API MANAGEMENT OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "apim_name" {
  description = "Name of API Management"
  value       = azurerm_api_management.main.name
}

output "apim_gateway_url" {
  description = "Gateway URL of API Management"
  value       = azurerm_api_management.main.gateway_url
}

output "apim_portal_url" {
  description = "Developer portal URL of API Management"
  value       = azurerm_api_management.main.developer_portal_url
}
