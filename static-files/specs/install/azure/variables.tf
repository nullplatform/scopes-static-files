variable "nrn" {
  description = "NullPlatform Resource Name for the scope"
  type        = string
}

variable "np_api_key" {
  description = "nullplatform API key for authentication"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Map of tags used to select and filter channels and agents"
  type        = map(string)
}

# ------------------------------------------------------------------------------
# Azure provider-config attributes
#
# These feed into `nullplatform_provider_config.static_files_configuration`.
# Required for any scope of type Static Files that targets Azure. See
# `scope-configuration.json.tpl` for the full schema and `README.md` for the
# list of pre-requisites each of these assumes exists.
# ------------------------------------------------------------------------------

variable "azure_subscription_id" {
  description = "Azure subscription where the scope's resources (CDN profile, DNS records) are created."
  type        = string
}

variable "azure_state_storage_account" {
  description = <<-EOT
    Storage account holding the OpenTofu state. The nullplatform agent writes one
    state file per scope here during the deployment workflow. Shared across every
    `provider_configs` entry — one state location, not one per environment. Must
    exist before any scope is created, and the agent's service principal needs
    the `Storage Blob Data Contributor` role on it. Note that `Contributor` on
    the resource group is NOT enough: it does not grant blob data-plane access.
  EOT
  type        = string
}

variable "azure_state_container" {
  description = "Blob container inside `azure_state_storage_account` where the state files are written."
  type        = string
}

variable "provider_configs" {
  description = <<-EOT
    One entry per environment/region. Each element creates its own
    `nullplatform_provider_config` resource, typically scoped to a different
    NRN (e.g. per environment) with its own resource group and Azure DNS zone.
    The `nrn` of each entry is used as the `for_each` key, so keep it stable to
    avoid recreating provider configs on unrelated changes.

    `azure_dns_zone_resource_group` is optional: leave it null and the zone is
    looked up in `azure_resource_group`.
  EOT
  type = list(object({
    nrn                           = string
    azure_resource_group          = string
    azure_dns_zone_name           = string
    azure_dns_zone_resource_group = optional(string)
  }))
}
