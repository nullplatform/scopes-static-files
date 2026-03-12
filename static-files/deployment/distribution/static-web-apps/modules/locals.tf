# =============================================================================
# Locals for Azure Static Web Apps Distribution
# =============================================================================

locals {
  # Use network_full_domain from network layer (provided via cross-module locals when composed)
  distribution_has_custom_domain = local.network_full_domain != ""
  distribution_full_domain       = local.network_full_domain

  distribution_tags = merge(var.distribution_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = "distribution/static-web-apps"
  })

  # Cross-module references (consumed by network/azure_dns)
  distribution_target_domain = azurerm_static_web_app.main.default_host_name
  distribution_record_type   = "CNAME"
}
