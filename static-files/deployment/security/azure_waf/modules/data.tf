# The WAF policy is a customer-owned prerequisite, like the Front Door profile.
# The scope never creates, updates or destroys it.
data "azurerm_cdn_frontdoor_firewall_policy" "shared" {
  name                = var.security_waf_policy_name
  resource_group_name = var.security_waf_policy_resource_group
}
