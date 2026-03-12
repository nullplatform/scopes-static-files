output "distribution_default_hostname" {
  description = "Azure Static Web App default hostname"
  value       = azurerm_static_web_app.main.default_host_name
}

output "distribution_target_domain" {
  description = "Target domain for DNS records (Static Web App hostname)"
  value       = local.distribution_target_domain
}

output "distribution_record_type" {
  description = "DNS record type (CNAME for Azure Static Web Apps)"
  value       = local.distribution_record_type
}

output "distribution_website_url" {
  description = "Website URL"
  value       = local.distribution_has_custom_domain ? "https://${local.distribution_full_domain}" : "https://${azurerm_static_web_app.main.default_host_name}"
}
