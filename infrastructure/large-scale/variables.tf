# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "mkt-compliance"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "primary_location" {
  description = "Primary Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "secondary_location" {
  description = "Secondary Azure region for resources"
  type        = string
  default     = "northeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER REGISTRY PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Premium"
}

# ---------------------------------------------------------------------------------------------------------------------
# POSTGRESQL PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
}

variable "postgres_sku_name" {
  description = "PostgreSQL SKU name (large scale: GP_Standard_D4ds_v4)"
  type        = string
  default     = "GP_Standard_D4ds_v4"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
  default     = 262144 # 256GB
}

variable "postgres_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "psqladmin"
  sensitive   = true
}

variable "postgres_database_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "compliance_db"
}

variable "postgres_backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 35
}

# ---------------------------------------------------------------------------------------------------------------------
# REDIS CACHE PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "redis_sku_name" {
  description = "Redis Cache SKU (Premium for geo-replication)"
  type        = string
  default     = "Premium"
}

variable "redis_family" {
  description = "Redis Cache family (P for Premium)"
  type        = string
  default     = "P"
}

variable "redis_capacity" {
  description = "Redis Cache capacity (1-5 for P family)"
  type        = number
  default     = 1 # 6GB
}

# ---------------------------------------------------------------------------------------------------------------------
# STORAGE PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication" {
  description = "Storage account replication type"
  type        = string
  default     = "GZRS" # Geo-zone-redundant
}

variable "blob_containers" {
  description = "List of blob containers to create"
  type        = list(string)
  default     = ["articles", "gtcs", "mlflow-artifacts", "cache"]
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER APPS PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "container_apps_min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 3
}

variable "container_apps_max_replicas" {
  description = "Maximum number of container replicas"
  type        = number
  default     = 20
}

variable "container_cpu" {
  description = "CPU cores for container"
  type        = number
  default     = 2.0
}

variable "container_memory" {
  description = "Memory in GB for container"
  type        = string
  default     = "4Gi"
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

# ---------------------------------------------------------------------------------------------------------------------
# API MANAGEMENT PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "apim_sku_name" {
  description = "API Management SKU"
  type        = string
  default     = "Premium_1"
}

variable "apim_publisher_name" {
  description = "API Management publisher name"
  type        = string
  default     = "Marketing Compliance Team"
}

variable "apim_publisher_email" {
  description = "API Management publisher email"
  type        = string
  default     = "api-admin@company.com"
}

# ---------------------------------------------------------------------------------------------------------------------
# FRONT DOOR PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "front_door_sku" {
  description = "Azure Front Door SKU"
  type        = string
  default     = "Premium_AzureFrontDoor"
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "premium"
}

# ---------------------------------------------------------------------------------------------------------------------
# EXTERNAL API PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "cudaap_api_endpoint" {
  description = "CUDAAP Azure OpenAI endpoint"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cudaap_api_key" {
  description = "CUDAAP Azure OpenAI API key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "smart_search_api_endpoint" {
  description = "Smart Search API endpoint"
  type        = string
  default     = ""
  sensitive   = true
}

variable "smart_search_api_key" {
  description = "Smart Search API key"
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------------------------------------------------
# MLFLOW PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "mlflow_tracking_uri" {
  description = "MLflow tracking URI (optional, defaults to blob storage)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# TAGS
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Marketing-Content-Compliance"
    Environment = "Production"
    ManagedBy   = "Terraform"
    Scale       = "Large"
  }
}
