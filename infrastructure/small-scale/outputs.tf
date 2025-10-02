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

output "acr_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
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

output "postgres_database_name" {
  description = "Name of the PostgreSQL database"
  value       = azurerm_postgresql_flexible_server_database.main.name
}

output "postgres_admin_username" {
  description = "PostgreSQL administrator username"
  value       = var.postgres_admin_username
  sensitive   = true
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${var.postgres_admin_username}:${random_password.postgres_password.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
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

output "storage_connection_string" {
  description = "Storage account connection string"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "blob_containers" {
  description = "Names of the blob containers"
  value       = [for c in azurerm_storage_container.containers : c.name]
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

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
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

output "container_app_fqdn" {
  description = "Fully qualified domain name of the Container App"
  value       = azurerm_container_app.api.ingress[0].fqdn
}

output "container_app_url" {
  description = "URL of the Container App"
  value       = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

output "container_app_identity_principal_id" {
  description = "Principal ID of the Container App managed identity"
  value       = azurerm_container_app.api.identity[0].principal_id
}

# ---------------------------------------------------------------------------------------------------------------------
# LOG ANALYTICS OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}
