# =============================================================================
# Front Door WAF attachment
#
# The scope owns only the security policy that associates the shared WAF
# policy with its own custom domain. Other scopes of the profile are not
# affected. Consumes local.distribution_front_door_profile_id and
# local.distribution_custom_domain_id from distribution/front-door.
# =============================================================================

resource "azurerm_cdn_frontdoor_security_policy" "static" {
  # distribution/front-door caps distribution_app_name at 83 chars (its
  # "-domain"/"-origin" names hit Azure's 90-char limit first), so this name
  # stays within the same limit.
  name                     = "${var.distribution_app_name}-waf"
  cdn_frontdoor_profile_id = local.distribution_front_door_profile_id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = data.azurerm_cdn_frontdoor_firewall_policy.shared.id

      association {
        domain {
          cdn_frontdoor_domain_id = local.distribution_custom_domain_id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}
