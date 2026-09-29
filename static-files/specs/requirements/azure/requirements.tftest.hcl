# =============================================================================
# Unit tests for specs/requirements/azure
#
# Run: tofu init -backend=false && tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_resource "azurerm_cdn_frontdoor_profile" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/static-files-afd"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_endpoint" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/static-files-afd/afdEndpoints/mock-endpoint"
      host_name = "mock-endpoint-abcd.z01.azurefd.net"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_firewall_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/staticfileswaf"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-static-files-afd"
      principal_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      location = "eastus2"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_secret" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/static-files-afd/secrets/customer-certificate"
    }
  }

  mock_resource "azurerm_role_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  agent_principal_id             = "22222222-2222-2222-2222-222222222222"
  front_door_profile_name        = "static-files-afd"
  front_door_resource_group_name = "cdn-rg"
  state_storage_account_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/state-rg/providers/Microsoft.Storage/storageAccounts/tfstate"
  state_container_name           = "tfstate"
  dns_zone_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnsZones/example.com"
  assets_storage_account_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/assets-rg/providers/Microsoft.Storage/storageAccounts/assets"
}

run "defaults_create_profile_endpoints_and_four_role_assignments" {
  command = plan

  assert {
    condition     = length(azurerm_cdn_frontdoor_profile.this) == 1
    error_message = "Expected one Front Door profile"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].sku_name == "Standard_AzureFrontDoor"
    error_message = "Default SKU should be Standard_AzureFrontDoor"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_endpoint.this) == 3
    error_message = "Expected one endpoint per default environment"
  }

  assert {
    condition     = length(azurerm_role_assignment.agent) == 4
    error_message = "Expected 4 role assignments, got ${length(azurerm_role_assignment.agent)}"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_firewall_policy.this) == 0
    error_message = "No WAF policy by default"
  }

  assert {
    condition     = azurerm_role_assignment.agent["state_container"].scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/state-rg/providers/Microsoft.Storage/storageAccounts/tfstate/blobServices/default/containers/tfstate"
    error_message = "Storage Blob Data Contributor should be scoped to the state container"
  }

  assert {
    condition     = azurerm_role_assignment.agent["state_container"].role_definition_name == "Storage Blob Data Contributor"
    error_message = "State container role should be Storage Blob Data Contributor"
  }

  assert {
    condition     = azurerm_role_assignment.agent["dns_zone"].role_definition_name == "DNS Zone Contributor" && azurerm_role_assignment.agent["dns_zone"].scope == var.dns_zone_id
    error_message = "DNS Zone Contributor should be scoped to the DNS zone"
  }

  assert {
    condition     = azurerm_role_assignment.agent["assets_storage_account"].role_definition_name == "Reader" && azurerm_role_assignment.agent["assets_storage_account"].scope == var.assets_storage_account_id
    error_message = "Reader should be scoped to the assets storage account"
  }

  assert {
    condition     = azurerm_role_assignment.agent["front_door_profile"].role_definition_name == "CDN Profile Contributor"
    error_message = "Front Door profile role should be CDN Profile Contributor"
  }

  assert {
    condition     = alltrue([for k, v in azurerm_role_assignment.agent : v.principal_id == var.agent_principal_id && v.principal_type == "ServicePrincipal"])
    error_message = "Every assignment should target the agent principal as a ServicePrincipal"
  }

  assert {
    condition     = output.waf_policy_id == null && output.waf_policy_name == null
    error_message = "WAF outputs should be null when no policy is created"
  }
}

run "profile_role_is_scoped_to_the_created_profile" {
  command = apply

  assert {
    condition     = azurerm_role_assignment.agent["front_door_profile"].scope == azurerm_cdn_frontdoor_profile.this[0].id
    error_message = "CDN Profile Contributor should be scoped to the created profile"
  }

  assert {
    condition     = output.front_door_profile_id == azurerm_cdn_frontdoor_profile.this[0].id
    error_message = "front_door_profile_id should be the created profile id"
  }

  assert {
    condition     = output.front_door_endpoint_host_names["production"] == "mock-endpoint-abcd.z01.azurefd.net"
    error_message = "front_door_endpoint_host_names should map env to host name"
  }

  assert {
    condition     = length(output.role_assignment_ids) == 4
    error_message = "role_assignment_ids should have one entry per assignment"
  }
}

run "endpoints_are_named_prefix_dash_environment" {
  command = plan

  variables {
    environments               = ["dev", "prd"]
    front_door_endpoint_prefix = "fsj-static"
    tags                       = { team = "platform" }
  }

  assert {
    condition     = output.front_door_endpoint_names == { dev = "fsj-static-dev", prd = "fsj-static-prd" }
    error_message = "Endpoint names should be <prefix>-<env>, got ${jsonencode(output.front_door_endpoint_names)}"
  }

  assert {
    condition     = alltrue([for e in azurerm_cdn_frontdoor_endpoint.this : e.enabled])
    error_message = "Endpoints should be enabled"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].tags == tomap({ team = "platform" }) && azurerm_cdn_frontdoor_endpoint.this["dev"].tags == tomap({ team = "platform" })
    error_message = "Tags should apply to the profile and the endpoints"
  }

  assert {
    condition     = output.front_door_profile_name == "static-files-afd" && output.front_door_resource_group_name == "cdn-rg"
    error_message = "Profile name and resource group outputs should match the inputs"
  }
}

run "existing_profile_creates_no_front_door" {
  command = plan

  variables {
    create_front_door              = false
    existing_front_door_profile_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/other-rg/providers/Microsoft.Cdn/profiles/existing-afd"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_profile.this) == 0 && length(azurerm_cdn_frontdoor_endpoint.this) == 0
    error_message = "No profile or endpoints when create_front_door is false"
  }

  assert {
    condition     = azurerm_role_assignment.agent["front_door_profile"].scope == var.existing_front_door_profile_id
    error_message = "CDN Profile Contributor should be scoped to the existing profile"
  }

  assert {
    condition     = output.front_door_profile_id == var.existing_front_door_profile_id
    error_message = "front_door_profile_id should be the existing profile id"
  }

  assert {
    condition     = output.front_door_profile_name == "existing-afd" && output.front_door_resource_group_name == "other-rg"
    error_message = "Profile name and resource group should be parsed from the existing id"
  }

  assert {
    condition     = output.front_door_endpoint_names == {}
    error_message = "No endpoint names when create_front_door is false"
  }
}

run "existing_profile_requires_its_id" {
  command = plan

  variables {
    create_front_door = false
  }

  expect_failures = [azurerm_role_assignment.agent]
}

run "role_assignments_can_be_disabled" {
  command = plan

  variables {
    create_role_assignments = false
    agent_principal_id      = ""
  }

  assert {
    condition     = length(azurerm_role_assignment.agent) == 0
    error_message = "No role assignments when create_role_assignments is false"
  }

  assert {
    condition     = output.role_assignment_ids == {}
    error_message = "role_assignment_ids should be empty"
  }
}

run "missing_principal_id_fails_when_assignments_are_on" {
  command = plan

  variables {
    agent_principal_id = ""
  }

  expect_failures = [azurerm_role_assignment.agent]
}

run "waf_policy_is_created_with_its_reader_assignment" {
  command = apply

  variables {
    create_waf_policy = true
    waf_policy_name   = "staticfileswaf"
    front_door_sku    = "Premium_AzureFrontDoor"
    tags              = { team = "platform" }
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_firewall_policy.this) == 1
    error_message = "Expected one WAF policy"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.this[0].sku_name == "Premium_AzureFrontDoor"
    error_message = "WAF policy SKU should match the profile SKU"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.this[0].mode == "Prevention" && azurerm_cdn_frontdoor_firewall_policy.this[0].enabled
    error_message = "WAF policy should be enabled in Prevention mode by default"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.this[0].tags == tomap({ team = "platform" })
    error_message = "Tags should apply to the WAF policy"
  }

  assert {
    condition     = length(azurerm_role_assignment.agent) == 5
    error_message = "Expected a fifth role assignment for the WAF policy"
  }

  assert {
    condition     = azurerm_role_assignment.agent["waf_policy"].role_definition_name == "Reader" && azurerm_role_assignment.agent["waf_policy"].scope == azurerm_cdn_frontdoor_firewall_policy.this[0].id
    error_message = "Reader should be scoped to the WAF policy"
  }

  assert {
    condition     = output.waf_policy_name == "staticfileswaf" && output.waf_policy_id == azurerm_cdn_frontdoor_firewall_policy.this[0].id
    error_message = "WAF outputs should expose the created policy"
  }
}

run "existing_waf_policy_gets_the_reader_assignment" {
  command = plan

  variables {
    existing_waf_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sec-rg/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/existingwaf"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_firewall_policy.this) == 0
    error_message = "No WAF policy is created for an existing one"
  }

  assert {
    condition     = azurerm_role_assignment.agent["waf_policy"].scope == var.existing_waf_policy_id
    error_message = "Reader should be scoped to the existing WAF policy"
  }
}

run "invalid_sku_is_rejected" {
  command = plan

  variables {
    front_door_sku = "Classic_AzureFrontDoor"
  }

  expect_failures = [var.front_door_sku]
}

run "invalid_waf_mode_is_rejected" {
  command = plan

  variables {
    waf_mode = "Block"
  }

  expect_failures = [var.waf_mode]
}

run "invalid_waf_policy_name_is_rejected" {
  command = plan

  variables {
    create_waf_policy = true
    waf_policy_name   = "static-files-waf"
  }

  expect_failures = [var.waf_policy_name]
}

run "endpoint_name_with_invalid_characters_is_rejected" {
  command = plan

  variables {
    front_door_endpoint_prefix = "static_files"
  }

  expect_failures = [var.front_door_endpoint_prefix]
}

run "endpoint_name_longer_than_46_chars_is_rejected" {
  command = plan

  variables {
    front_door_endpoint_prefix = "a-very-long-endpoint-prefix-for-static-files"
  }

  expect_failures = [azurerm_cdn_frontdoor_endpoint.this]
}

run "environment_with_invalid_characters_is_rejected" {
  command = plan

  variables {
    environments = ["development", "prod_"]
  }

  expect_failures = [var.environments]
}

run "longest_endpoint_name_is_accepted" {
  command = plan

  variables {
    environments               = ["production"]
    front_door_endpoint_prefix = "a-35-char-endpoint-prefix-abcdefghi"
  }

  assert {
    condition     = length(output.front_door_endpoint_names["production"]) == 46
    error_message = "A 46-char endpoint name should be accepted"
  }
}

run "profile_requires_a_resource_group" {
  command = plan

  variables {
    front_door_resource_group_name = ""
  }

  expect_failures = [azurerm_cdn_frontdoor_profile.this]
}

run "customer_certificate_is_off_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_cdn_frontdoor_profile.this[0].identity) == 0
    error_message = "The profile should have no managed identity without a customer certificate"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_secret.customer_certificate) == 0
    error_message = "No Front Door secret without a customer certificate"
  }

  assert {
    condition     = length(azurerm_role_assignment.front_door_key_vault) == 0
    error_message = "No Key Vault role assignment without a customer certificate"
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.front_door) == 0 && length(data.azurerm_resource_group.front_door) == 0
    error_message = "No user-assigned identity (nor resource group lookup) without a customer certificate"
  }

  assert {
    condition     = output.front_door_certificate_secret_name == null && output.front_door_principal_id == null && output.front_door_identity_id == null
    error_message = "Certificate outputs should be null without a customer certificate"
  }
}

run "customer_certificate_creates_identity_role_and_secret" {
  command = apply

  variables {
    certificate_key_vault_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/kv-rg/providers/Microsoft.KeyVault/vaults/certs-kv"
    certificate_key_vault_certificate_id = "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_profile.this[0].identity).type == "UserAssigned"
    error_message = "The profile should get a UserAssigned identity"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_profile.this[0].identity).identity_ids == toset([azurerm_user_assigned_identity.front_door[0].id])
    error_message = "The profile identity should be the module's user-assigned identity"
  }

  assert {
    condition     = azurerm_user_assigned_identity.front_door[0].name == "id-static-files-afd"
    error_message = "The identity name should default to id-<front_door_profile_name>"
  }

  assert {
    condition     = azurerm_user_assigned_identity.front_door[0].resource_group_name == "cdn-rg" && azurerm_user_assigned_identity.front_door[0].location == "eastus2"
    error_message = "The identity should live in the profile's resource group and take its location"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_secret.customer_certificate[0].name == "customer-certificate"
    error_message = "The secret should be named front_door_certificate_secret_name (default customer-certificate)"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_secret.customer_certificate[0].cdn_frontdoor_profile_id == azurerm_cdn_frontdoor_profile.this[0].id
    error_message = "The secret should live in the created profile"
  }

  assert {
    condition     = one(one(azurerm_cdn_frontdoor_secret.customer_certificate[0].secret).customer_certificate).key_vault_certificate_id == "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com"
    error_message = "The secret should reference the versionless certificate id"
  }

  assert {
    condition     = azurerm_role_assignment.front_door_key_vault[0].role_definition_name == "Key Vault Secrets User"
    error_message = "The profile identity should get Key Vault Secrets User"
  }

  assert {
    condition     = azurerm_role_assignment.front_door_key_vault[0].scope == var.certificate_key_vault_id
    error_message = "Key Vault Secrets User should be scoped to the certificate's vault"
  }

  assert {
    condition     = azurerm_role_assignment.front_door_key_vault[0].principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "Key Vault Secrets User should target the user-assigned identity's principal id"
  }

  assert {
    condition     = azurerm_role_assignment.front_door_key_vault[0].principal_type == "ServicePrincipal"
    error_message = "The profile identity is a ServicePrincipal"
  }

  assert {
    condition     = output.front_door_certificate_secret_name == "customer-certificate"
    error_message = "front_door_certificate_secret_name should feed distribution.azure_front_door_certificate_secret"
  }

  assert {
    condition     = output.front_door_principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "front_door_principal_id should be the user-assigned identity's principal id"
  }

  assert {
    condition     = output.front_door_identity_id == azurerm_user_assigned_identity.front_door[0].id
    error_message = "front_door_identity_id should be the user-assigned identity id"
  }

  assert {
    condition     = length(azurerm_role_assignment.agent) == 4
    error_message = "The agent's role assignments are unchanged by the customer certificate"
  }
}

run "customer_certificate_secret_name_is_configurable" {
  command = plan

  variables {
    certificate_key_vault_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/kv-rg/providers/Microsoft.KeyVault/vaults/certs-kv"
    certificate_key_vault_certificate_id = "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com"
    front_door_certificate_secret_name   = "wildcard-np-example-com"
    front_door_identity_name             = "id-fsj-static-files"
    front_door_identity_location         = "brazilsouth"
  }

  assert {
    condition     = azurerm_user_assigned_identity.front_door[0].name == "id-fsj-static-files" && azurerm_user_assigned_identity.front_door[0].location == "brazilsouth"
    error_message = "front_door_identity_name and front_door_identity_location should override the defaults"
  }

  assert {
    condition     = length(data.azurerm_resource_group.front_door) == 0
    error_message = "An explicit location needs no resource group lookup"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_secret.customer_certificate[0].name == "wildcard-np-example-com"
    error_message = "The secret should take front_door_certificate_secret_name"
  }

  assert {
    condition     = output.front_door_certificate_secret_name == "wildcard-np-example-com"
    error_message = "The output should follow front_door_certificate_secret_name"
  }
}

run "versioned_certificate_id_is_rejected" {
  command = plan

  variables {
    certificate_key_vault_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/kv-rg/providers/Microsoft.KeyVault/vaults/certs-kv"
    certificate_key_vault_certificate_id = "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com/0123456789abcdef0123456789abcdef"
  }

  expect_failures = [var.certificate_key_vault_certificate_id]
}

run "invalid_certificate_secret_name_is_rejected" {
  command = plan

  variables {
    front_door_certificate_secret_name = "customer_certificate"
  }

  expect_failures = [var.front_door_certificate_secret_name]
}

run "customer_certificate_requires_a_created_profile" {
  command = plan

  variables {
    create_front_door                    = false
    existing_front_door_profile_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/other-rg/providers/Microsoft.Cdn/profiles/existing-afd"
    certificate_key_vault_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/kv-rg/providers/Microsoft.KeyVault/vaults/certs-kv"
    certificate_key_vault_certificate_id = "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com"
  }

  expect_failures = [azurerm_role_assignment.front_door_key_vault]
}

run "customer_certificate_requires_the_key_vault_id" {
  command = plan

  variables {
    certificate_key_vault_certificate_id = "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com"
  }

  expect_failures = [azurerm_role_assignment.front_door_key_vault]
}

run "invalid_identity_name_is_rejected" {
  command = plan

  variables {
    front_door_identity_name = "-bad name"
  }

  expect_failures = [var.front_door_identity_name]
}
