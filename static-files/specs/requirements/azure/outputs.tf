output "front_door_profile_id" {
  description = "Id of the Front Door profile (created or existing)."
  value       = var.create_front_door ? azurerm_cdn_frontdoor_profile.this[0].id : (var.existing_front_door_profile_id != "" ? var.existing_front_door_profile_id : null)
}

output "front_door_profile_name" {
  description = "Name of the Front Door profile. Feeds distribution.azure_front_door_profile."
  value       = var.create_front_door ? azurerm_cdn_frontdoor_profile.this[0].name : try(regex("/profiles/([^/]+)$", var.existing_front_door_profile_id)[0], null)
}

output "front_door_resource_group_name" {
  description = "Resource group of the Front Door profile. Feeds distribution.azure_front_door_resource_group."
  value       = var.create_front_door ? azurerm_cdn_frontdoor_profile.this[0].resource_group_name : try(regex("(?i)/resourceGroups/([^/]+)/", var.existing_front_door_profile_id)[0], null)
}

output "front_door_endpoint_names" {
  description = "Map of environment to endpoint name. Feeds distribution.azure_front_door_endpoint."
  value       = { for env, e in azurerm_cdn_frontdoor_endpoint.this : env => e.name }
}

output "front_door_endpoint_host_names" {
  description = "Map of environment to endpoint host name (<name>-<hash>.z01.azurefd.net)."
  value       = { for env, e in azurerm_cdn_frontdoor_endpoint.this : env => e.host_name }
}

output "waf_policy_id" {
  description = "Id of the created WAF policy, or null when not created."
  value       = var.create_waf_policy ? azurerm_cdn_frontdoor_firewall_policy.this[0].id : null
}

output "waf_policy_name" {
  description = "Name of the created WAF policy, or null when not created. Feeds security.azure_waf_policy_name."
  value       = var.create_waf_policy ? azurerm_cdn_frontdoor_firewall_policy.this[0].name : null
}

output "role_assignment_ids" {
  description = "Map of assignment key (state_container, front_door_profile, dns_zone, assets_storage_account, waf_policy) to role assignment id."
  value       = { for k, ra in azurerm_role_assignment.agent : k => ra.id }
}

output "front_door_certificate_secret_name" {
  description = "Name of the Front Door secret with the customer certificate, or null when not used. Feeds distribution.azure_front_door_certificate_secret."
  value       = local.use_customer_certificate ? azurerm_cdn_frontdoor_secret.customer_certificate[0].name : null
}

output "front_door_principal_id" {
  description = "Principal id of the profile's system-assigned identity, or null when the profile has none."
  value       = try(azurerm_cdn_frontdoor_profile.this[0].identity[0].principal_id, null)
}
