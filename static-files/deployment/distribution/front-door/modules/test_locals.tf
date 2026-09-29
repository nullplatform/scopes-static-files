# =============================================================================
# Test-only locals and variables
#
# Bridges the network_* locals and the provider variables that the composed
# root module gets from network/azure_dns and provider/azure. Skipped by
# compose_modules (test_*.tf).
# =============================================================================

variable "network_full_domain" {
  description = "Test-only: full domain from the network layer"
  type        = string
  default     = ""
}

variable "network_domain" {
  description = "Test-only: root domain from the network layer"
  type        = string
  default     = ""
}

variable "network_subdomain" {
  description = "Subdomain for the distribution"
  type        = string
  default     = ""
}

variable "network_dns_zone_name" {
  description = "Azure DNS zone name"
  type        = string
  default     = ""
}

variable "network_dns_zone_resource_group" {
  description = "Resource group of the Azure DNS zone"
  type        = string
  default     = ""
}

variable "azure_provider" {
  description = "Azure provider configuration"
  type = object({
    subscription_id = string
    resource_group  = string
    storage_account = string
    container       = string
  })
}

locals {
  network_full_domain = var.network_full_domain
  network_domain      = var.network_domain
}
