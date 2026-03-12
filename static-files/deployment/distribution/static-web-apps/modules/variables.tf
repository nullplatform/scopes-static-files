variable "distribution_app_name" {
  description = "Application name (used for resource naming)"
  type        = string
}

variable "distribution_sku_tier" {
  description = "SKU tier for Azure Static Web App (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "distribution_location" {
  description = "Azure region for the Static Web App"
  type        = string
  default     = "eastus2"
}

variable "distribution_artifact_url" {
  description = "URL of the artifact in blob storage (used as trigger for redeployment)"
  type        = string
}

variable "distribution_artifact_dir" {
  description = "Local directory containing downloaded artifact files for deployment"
  type        = string
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}
