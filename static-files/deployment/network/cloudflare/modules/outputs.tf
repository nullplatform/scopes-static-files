output "network_full_domain" {
  description = "Full domain name (subdomain.domain or just domain)"
  value       = local.network_full_domain
}

output "network_fqdn" {
  description = "Fully qualified domain name"
  value       = local.network_full_domain
}

output "network_website_url" {
  description = "Website URL"
  value       = "https://${local.network_full_domain}"
}
