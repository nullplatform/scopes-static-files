output "distribution_storage_account" {
  description = "Azure Storage account name"
  value       = var.distribution_storage_account
}

output "distribution_container_name" {
  description = "Azure Storage container name"
  value       = var.distribution_container_name
}

output "distribution_blob_prefix" {
  description = "Blob prefix path for this scope"
  value       = var.distribution_blob_prefix
}

output "distribution_front_door_profile" {
  description = "Shared Front Door profile name"
  value       = var.distribution_front_door_profile
}

output "distribution_front_door_endpoint_hostname" {
  description = "Shared Front Door endpoint hostname (CNAME target)"
  value       = data.azurerm_cdn_frontdoor_endpoint.shared.host_name
}

output "distribution_route_name" {
  description = "Front Door route owned by this scope"
  value       = azurerm_cdn_frontdoor_route.static.name
}

output "distribution_target_domain" {
  description = "Target domain for DNS records (shared endpoint hostname)"
  value       = local.distribution_target_domain
}

output "distribution_record_type" {
  description = "DNS record type (CNAME for Front Door)"
  value       = local.distribution_record_type
}

output "distribution_website_url" {
  description = "Website URL (custom domain only; the shared endpoint hostname does not serve this scope)"
  value       = "https://${local.distribution_full_domain}"
}

output "distribution_custom_domain" {
  description = "Custom domain served by this scope"
  value       = azurerm_cdn_frontdoor_custom_domain.static.host_name
}

output "distribution_validation_record" {
  description = "TXT record that validates the custom domain"
  value       = azurerm_dns_txt_record.custom_domain_validation.fqdn
}
