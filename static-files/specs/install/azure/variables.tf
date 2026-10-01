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
  description = <<-EOT
    Default Azure subscription where the scope's resources (CDN profile, DNS
    records) are created. Override it per environment with
    `provider_configs[*].azure_subscription_id`.
  EOT
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

variable "azure_state_resource_group" {
  description = "Resource group of the state storage account. Empty means the entry's own `azure_resource_group`."
  type        = string
  default     = ""
}

variable "azure_state_auth" {
  description = "How OpenTofu authenticates to the state storage account: `azuread` (agent identity, needs Storage Blob Data Contributor) or `key` (account keys, shared-key access must be enabled)."
  type        = string
  default     = "azuread"

  validation {
    condition     = contains(["azuread", "key"], var.azure_state_auth)
    error_message = "azure_state_auth must be \"azuread\" or \"key\"."
  }
}

variable "provider_configs" {
  description = <<-EOT
    One entry per environment/region. Each element creates its own
    `nullplatform_provider_config` resource, typically scoped to a different
    NRN (e.g. per environment) with its own resource group and Azure DNS zone.
    The `nrn` of each entry is used as the `for_each` key, so keep it stable to
    avoid recreating provider configs on unrelated changes.

    `azure_subscription_id` is optional and falls back to
    `var.azure_subscription_id`. Set it to target a different subscription per
    environment, which is the common Azure landing-zone layout.

    `azure_dns_zone_resource_group` is the resource group that holds the DNS zone;
    it may differ from `azure_resource_group`.

    `azure_front_door_profile` and `azure_front_door_endpoint` name the Front Door
    profile and endpoint shared by every static-files scope of that environment;
    create them before the first deployment.

    The remaining optional fields tune the Front Door behavior and default to
    the layer's own defaults (see the Azure section of the README):
    `azure_front_door_cached_path_prefixes`, `azure_front_door_cache_days`,
    `azure_front_door_security_headers`, `azure_front_door_content_security_policy`.

    `azure_front_door_certificate_secret` names the Front Door secret in the
    shared profile that points to a Key Vault certificate covering the scopes'
    domains (the requirements module's `front_door_certificate_secret_name`).
    Unset or empty, each scope gets a Front Door managed certificate.

    `azure_assets_storage_account` is the storage account (static website
    enabled) that CI uploads bundles to. Required to create scopes: the scope
    creates its Front Door origin on it before any deployment exists.

    `azure_security = "azure_waf"` attaches the existing Front Door WAF policy
    `azure_waf_policy_name` (in `azure_waf_policy_resource_group`, default
    `azure_resource_group`) to every scope's custom domain; `none` skips it.
  EOT
  type = list(object({
    nrn                             = string
    azure_subscription_id           = optional(string)
    azure_resource_group            = string
    azure_dns_zone_name             = string
    azure_dns_zone_resource_group   = string
    azure_front_door_profile        = string
    azure_front_door_endpoint       = string
    azure_front_door_resource_group = optional(string)
    azure_assets_storage_account    = optional(string)

    azure_front_door_cached_path_prefixes    = optional(list(string), ["/static/"])
    azure_front_door_cache_days              = optional(number, 7)
    azure_front_door_security_headers        = optional(bool, false)
    azure_front_door_content_security_policy = optional(string, "")
    azure_front_door_certificate_secret      = optional(string)

    azure_security                  = optional(string, "none")
    azure_waf_policy_name           = optional(string)
    azure_waf_policy_resource_group = optional(string)
  }))
}
