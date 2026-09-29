################################################################################
# Static-files scope — Azure requirements
#
# What the scope expects to exist before its first deployment and never
# creates itself: the shared Front Door profile, one endpoint per environment,
# optionally a WAF policy and a customer certificate (Front Door secret), and
# the agent identity's role assignments. The
# outputs feed the scope-configuration provider config of each environment.
################################################################################

locals {
  front_door_profile_id = var.create_front_door ? azurerm_cdn_frontdoor_profile.this[0].id : var.existing_front_door_profile_id

  waf_policy_id = var.create_waf_policy ? azurerm_cdn_frontdoor_firewall_policy.this[0].id : (
    var.existing_waf_policy_id != "" ? var.existing_waf_policy_id : null
  )
  assign_waf_policy = var.create_waf_policy || var.existing_waf_policy_id != ""

  use_customer_certificate = var.certificate_key_vault_certificate_id != ""

  role_assignments = !var.create_role_assignments ? {} : merge(
    {
      state_container = {
        scope = "${var.state_storage_account_id}/blobServices/default/containers/${var.state_container_name}"
        role  = "Storage Blob Data Contributor"
      }
      front_door_profile = {
        scope = local.front_door_profile_id
        role  = "CDN Profile Contributor"
      }
      dns_zone = {
        scope = var.dns_zone_id
        role  = "DNS Zone Contributor"
      }
      assets_storage_account = {
        scope = var.assets_storage_account_id
        role  = "Reader"
      }
    },
    local.assign_waf_policy ? {
      waf_policy = {
        scope = local.waf_policy_id
        role  = var.waf_policy_role_definition_name
      }
    } : {}
  )
}

resource "azurerm_cdn_frontdoor_profile" "this" {
  count = var.create_front_door ? 1 : 0

  name                = var.front_door_profile_name
  resource_group_name = var.front_door_resource_group_name
  sku_name            = var.front_door_sku
  tags                = var.tags

  # Front Door reads the customer certificate from Key Vault with this
  # identity. Added in place on an existing profile, never a replacement.
  dynamic "identity" {
    for_each = local.use_customer_certificate ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  lifecycle {
    precondition {
      condition     = var.front_door_resource_group_name != ""
      error_message = "front_door_resource_group_name is required when create_front_door is true."
    }
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  for_each = var.create_front_door ? toset(var.environments) : toset([])

  name                     = "${var.front_door_endpoint_prefix}-${each.key}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this[0].id
  enabled                  = true
  tags                     = var.tags

  # The variable validations cover the characters; the combined length
  # needs both variables, which validation blocks can reference only from
  # OpenTofu 1.9 / Terraform 1.9.
  lifecycle {
    precondition {
      condition     = length("${var.front_door_endpoint_prefix}-${each.key}") <= 46
      error_message = "Endpoint name ${var.front_door_endpoint_prefix}-${each.key} is longer than 46 chars; shorten front_door_endpoint_prefix or the environment name."
    }
  }
}

# Empty on purpose: the customer adds custom rules. Managed rule sets
# (DefaultRuleSet, BotManager) need Premium_AzureFrontDoor.
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  count = var.create_waf_policy ? 1 : 0

  name                = var.waf_policy_name
  resource_group_name = var.front_door_resource_group_name
  sku_name            = var.front_door_sku
  enabled             = true
  mode                = var.waf_mode
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = var.front_door_resource_group_name != ""
      error_message = "front_door_resource_group_name is required when create_waf_policy is true."
    }
  }
}

resource "azurerm_role_assignment" "agent" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = var.agent_principal_id
  principal_type       = var.agent_principal_type

  lifecycle {
    precondition {
      condition     = var.agent_principal_id != ""
      error_message = "agent_principal_id is required when create_role_assignments is true (the object id of the agent's service principal or managed identity)."
    }

    precondition {
      condition     = var.create_front_door || var.existing_front_door_profile_id != ""
      error_message = "existing_front_door_profile_id is required when create_front_door is false."
    }

    precondition {
      condition     = var.state_storage_account_id != "" && var.dns_zone_id != "" && var.assets_storage_account_id != ""
      error_message = "state_storage_account_id, dns_zone_id and assets_storage_account_id are required when create_role_assignments is true."
    }
  }
}

# =============================================================================
# Customer certificate: one Front Door secret in the shared profile that every
# scope references (distribution.azure_front_door_certificate_secret).
# =============================================================================
resource "azurerm_role_assignment" "front_door_key_vault" {
  count = local.use_customer_certificate ? 1 : 0

  scope                = var.certificate_key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = try(azurerm_cdn_frontdoor_profile.this[0].identity[0].principal_id, null)
  # The identity is created in the same apply: without the explicit type,
  # ARM looks the principal up in Entra ID, which may not have replicated it yet.
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true

  lifecycle {
    precondition {
      condition     = var.create_front_door
      error_message = "The customer certificate needs create_front_door = true: the module adds a managed identity to the profile it creates and does not change an existing profile's identity."
    }

    precondition {
      condition     = var.certificate_key_vault_id != ""
      error_message = "certificate_key_vault_id is required when certificate_key_vault_certificate_id is set."
    }
  }
}

# The versionless id makes Front Door follow renewals ("Latest"). Azure RBAC
# can take several minutes to reach Key Vault after the role assignment
# above: if the first apply fails here with a Key Vault access error, apply
# again (see the README).
resource "azurerm_cdn_frontdoor_secret" "customer_certificate" {
  count = local.use_customer_certificate ? 1 : 0

  name                     = var.front_door_certificate_secret_name
  cdn_frontdoor_profile_id = local.front_door_profile_id

  secret {
    customer_certificate {
      key_vault_certificate_id = var.certificate_key_vault_certificate_id
    }
  }

  depends_on = [azurerm_role_assignment.front_door_key_vault]
}
