# =============================================================================
# Unit tests for security/azure_waf module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_cdn_frontdoor_firewall_policy" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/security-rg/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/sharedwaf"
      sku_name = "Standard_AzureFrontDoor"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_security_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/securityPolicies/mock-waf"
    }
  }
}

variables {
  security_waf_policy_name           = "sharedwaf"
  security_waf_policy_resource_group = "security-rg"
  distribution_app_name              = "automation-development-tools-7"
  distribution_front_door_profile_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd"
  distribution_custom_domain_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/customDomains/automation-development-tools-7-domain"
}

run "looks_up_the_customer_owned_policy" {
  command = plan

  assert {
    condition     = data.azurerm_cdn_frontdoor_firewall_policy.shared.name == "sharedwaf"
    error_message = "The policy should be looked up by the configured name"
  }

  assert {
    condition     = data.azurerm_cdn_frontdoor_firewall_policy.shared.resource_group_name == "security-rg"
    error_message = "The policy should be looked up in the configured resource group"
  }
}

run "security_policy_is_named_after_the_scope" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_security_policy.static.name == "automation-development-tools-7-waf"
    error_message = "Security policy should be named '<app_name>-waf', got '${azurerm_cdn_frontdoor_security_policy.static.name}'"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_security_policy.static.cdn_frontdoor_profile_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd"
    error_message = "Security policy should live in the shared profile"
  }
}

run "associates_the_policy_with_the_scope_domain_only" {
  command = plan

  assert {
    condition     = one(one(azurerm_cdn_frontdoor_security_policy.static.security_policies).firewall).cdn_frontdoor_firewall_policy_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/security-rg/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/sharedwaf"
    error_message = "Security policy should reference the customer-owned WAF policy"
  }

  assert {
    condition     = [for d in one(one(one(azurerm_cdn_frontdoor_security_policy.static.security_policies).firewall).association).domain : d.cdn_frontdoor_domain_id] == ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/customDomains/automation-development-tools-7-domain"]
    error_message = "Security policy should be associated with this scope's custom domain only"
  }

  assert {
    condition     = one(one(one(azurerm_cdn_frontdoor_security_policy.static.security_policies).firewall).association).patterns_to_match == tolist(["/*"])
    error_message = "Security policy should cover every path of the domain"
  }
}

run "exposes_the_policy_id" {
  command = plan

  assert {
    condition     = output.security_waf_policy_id == data.azurerm_cdn_frontdoor_firewall_policy.shared.id
    error_message = "Output should expose the attached WAF policy id"
  }
}

# The distribution layer's longest suffix is "-domain"/"-origin" (7 chars), so
# the longest app name it accepts is 83 chars; "-waf" keeps that under 90.
run "longest_distribution_app_name_fits_the_90_char_limit" {
  command = plan

  variables {
    distribution_app_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-b-7"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_security_policy.static.name) == 87
    error_message = "Expected an 87-char security policy name, got ${length(azurerm_cdn_frontdoor_security_policy.static.name)}"
  }
}
