# =============================================================================
# Cloudflare provider requirement
#
# The provider layer (provider/aws) owns the root `terraform` block, and a
# module may declare `required_providers` only once. This is an override file
# on purpose: OpenTofu merges it into that block entry by entry, so the
# Cloudflare provider is required only when this layer is composed, and the
# provider layer does not need to know about it.
#
# compose_modules prefixes the file name, which keeps the `_override.tf`
# suffix OpenTofu looks for.
# =============================================================================
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
