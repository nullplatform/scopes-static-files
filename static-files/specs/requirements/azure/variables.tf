variable "agent_principal_id" {
  description = "Object id of the nullplatform agent identity (service principal or managed identity) that receives the role assignments. Required when create_role_assignments is true."
  type        = string
  default     = ""
}

variable "agent_principal_type" {
  description = "Principal type of agent_principal_id: ServicePrincipal (also for managed identities), User or Group."
  type        = string
  default     = "ServicePrincipal"

  validation {
    condition     = contains(["ServicePrincipal", "User", "Group"], var.agent_principal_type)
    error_message = "agent_principal_type must be ServicePrincipal, User or Group."
  }
}

variable "create_role_assignments" {
  description = "Whether to create the agent's role assignments."
  type        = bool
  default     = true
}

variable "state_storage_account_id" {
  description = "Resource id of the storage account that holds the scope's OpenTofu state. Required when create_role_assignments is true."
  type        = string
  default     = ""
}

variable "state_container_name" {
  description = "Blob container of the scope's OpenTofu state. The agent gets Storage Blob Data Contributor on this container only."
  type        = string
  default     = "tfstate"
}

variable "dns_zone_id" {
  description = "Resource id of the public Azure DNS zone the scopes write records into. Required when create_role_assignments is true."
  type        = string
  default     = ""
}

variable "assets_storage_account_id" {
  description = "Resource id of the static-website storage account that holds the frontend bundles (customer prerequisite). The agent gets Reader on it. Required when create_role_assignments is true."
  type        = string
  default     = ""
}

variable "create_front_door" {
  description = "Whether to create the Front Door profile and one endpoint per environment. When false, pass existing_front_door_profile_id."
  type        = bool
  default     = true
}

variable "existing_front_door_profile_id" {
  description = "Resource id of an existing Front Door profile, used when create_front_door is false."
  type        = string
  default     = ""
}

variable "front_door_profile_name" {
  description = "Name of the Front Door profile to create."
  type        = string
  default     = "static-files"
}

variable "front_door_resource_group_name" {
  description = "Resource group of the Front Door profile and, when created, the WAF policy."
  type        = string
  default     = ""
}

variable "front_door_sku" {
  description = "Front Door tier, also used for the WAF policy: Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku)
    error_message = "front_door_sku must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "environments" {
  description = "Environments that get their own Front Door endpoint."
  type        = list(string)
  default     = ["development", "staging", "production"]

  validation {
    condition     = alltrue([for env in var.environments : can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", env))])
    error_message = "Each environment must be letters, digits or hyphens and start and end with a letter or digit (it becomes part of the endpoint name)."
  }
}

variable "front_door_endpoint_prefix" {
  description = "Endpoint names are <prefix>-<environment>; each full name must be at most 46 chars."
  type        = string
  default     = "static-files"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,42}[A-Za-z0-9])?$", var.front_door_endpoint_prefix))
    error_message = "front_door_endpoint_prefix must be 1-44 letters, digits or hyphens and start and end with a letter or digit."
  }
}

variable "create_waf_policy" {
  description = "Whether to create an empty Front Door WAF policy (no rules) the scopes can attach with security.azure_security = azure_waf."
  type        = bool
  default     = false
}

variable "waf_policy_name" {
  description = "Name of the WAF policy to create: letters and digits only, starting with a letter, up to 128 chars."
  type        = string
  default     = "staticfileswaf"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,127}$", var.waf_policy_name))
    error_message = "waf_policy_name must be letters and digits only, start with a letter and be at most 128 chars."
  }
}

variable "waf_mode" {
  description = "Mode of the created WAF policy: Detection or Prevention."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "existing_waf_policy_id" {
  description = "Resource id of an existing Front Door WAF policy the scopes attach. The agent gets waf_policy_role_definition_name on it."
  type        = string
  default     = ""
}

variable "waf_policy_role_definition_name" {
  description = "Role assigned to the agent on the WAF policy (created or existing). Reader lets the scope read the policy; see the README for when Network Contributor is needed."
  type        = string
  default     = "Reader"
}

variable "tags" {
  description = "Tags applied to the Front Door profile, endpoints and WAF policy."
  type        = map(string)
  default     = {}
}

variable "certificate_key_vault_id" {
  description = "Resource id of the Key Vault (RBAC mode) that holds the customer certificate. Required when certificate_key_vault_certificate_id is set: the profile's managed identity gets Key Vault Secrets User on it."
  type        = string
  default     = ""
}

variable "certificate_key_vault_certificate_id" {
  description = "Versionless id of the Key Vault certificate the scopes serve (https://<vault>.vault.azure.net/certificates/<name>), e.g. a wildcard. Empty keeps a Front Door managed certificate per scope."
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("/[0-9A-Fa-f]{32}/?$", var.certificate_key_vault_certificate_id))
    error_message = "certificate_key_vault_certificate_id must be the versionless id (https://<vault>.vault.azure.net/certificates/<name>) so Front Door follows renewals; drop the trailing version segment."
  }
}

variable "front_door_certificate_secret_name" {
  description = "Name of the Front Door secret that references the customer certificate. Feeds distribution.azure_front_door_certificate_secret."
  type        = string
  default     = "customer-certificate"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]+$", var.front_door_certificate_secret_name)) && length(var.front_door_certificate_secret_name) <= 260
    error_message = "front_door_certificate_secret_name must be 2-260 letters, digits or hyphens and start with a letter or digit."
  }
}
