locals {
  # Expose network_domain for cross-module use (e.g., ACM certificate lookup)
  network_domain = var.network_domain

  # Compute full domain from domain + subdomain
  network_full_domain = var.network_subdomain != "" ? "${var.network_subdomain}.${var.network_domain}" : var.network_domain

  # Cloudflare only accepts ttl = 1 ("automatic") on a proxied record.
  network_cloudflare_ttl = var.network_cloudflare_proxied ? 1 : var.network_cloudflare_ttl
}
