data "azurerm_storage_account" "static" {
  name                = var.distribution_storage_account
  resource_group_name = var.azure_provider.resource_group
}

# The profile and the endpoint are prerequisites the customer creates once per
# environment. The scope never creates, updates or destroys them.
data "azurerm_cdn_frontdoor_profile" "shared" {
  name                = var.distribution_front_door_profile
  resource_group_name = var.distribution_front_door_resource_group
}

data "azurerm_cdn_frontdoor_endpoint" "shared" {
  name                = var.distribution_front_door_endpoint
  profile_name        = var.distribution_front_door_profile
  resource_group_name = var.distribution_front_door_resource_group
}

# The zone the custom domain lives in. Front Door validates the domain with a
# TXT record here, so the module needs the zone id and writes into it.
data "azurerm_dns_zone" "custom_domain" {
  name                = var.network_dns_zone_name
  resource_group_name = var.network_dns_zone_resource_group
}
