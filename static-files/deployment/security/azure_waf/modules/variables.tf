variable "security_waf_policy_name" {
  description = "Name of an existing Front Door WAF policy (Microsoft.Network/FrontDoorWebApplicationFirewallPolicies) to attach to the scope's custom domain"
  type        = string
}

variable "security_waf_policy_resource_group" {
  description = "Resource group that holds the Front Door WAF policy"
  type        = string
}
