# =============================================================================
# Cloudflare DNS Network
#
# Creates the DNS record for the distribution endpoint in a Cloudflare zone.
#
# Cloudflare has no equivalent of a Route 53 alias, so the record is always a
# CNAME to the distribution's own hostname. Cloudflare flattens CNAMEs at the
# zone apex on its own, which covers the case an alias exists for.
# =============================================================================

# Credentials come from the environment (CLOUDFLARE_API_TOKEN), the same way
# the AWS provider picks up the assumed role.
provider "cloudflare" {}

resource "cloudflare_dns_record" "main" {
  zone_id = var.network_cloudflare_zone_id
  name    = local.network_full_domain
  type    = "CNAME"
  content = local.distribution_target_domain
  ttl     = local.network_cloudflare_ttl
  proxied = var.network_cloudflare_proxied
  comment = "Managed by nullplatform (static-files scope)"
}
