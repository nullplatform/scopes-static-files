output "security_waf_policy_id" {
  description = "Id of the Front Door WAF policy attached to the scope's custom domain"
  value       = data.azurerm_cdn_frontdoor_firewall_policy.shared.id
}
