locals {
  distribution_full_domain       = local.network_full_domain
  distribution_has_custom_domain = local.network_full_domain != ""

  distribution_blob_prefix_trimmed = trim(var.distribution_blob_prefix, "/")
  distribution_origin_path         = local.distribution_blob_prefix_trimmed != "" ? "/${local.distribution_blob_prefix_trimmed}" : ""

  # Rule sets and rules only accept letters and digits, and at most 60 chars.
  # "<app>-<scope>-<id>" has hyphens, so strip them and cap the length.
  distribution_rule_set_name = substr(replace(var.distribution_app_name, "/[^A-Za-z0-9]/", ""), 0, 60)

  distribution_compressed_content_types = [
    "application/javascript",
    "application/json",
    "application/xml",
    "application/x-javascript",
    "image/svg+xml",
    "text/css",
    "text/html",
    "text/javascript",
    "text/plain",
    "text/xml",
  ]

  # Cross-module references (consumed by network/azure_dns): the CNAME points
  # at the shared endpoint; Front Door then routes by Host header.
  distribution_target_domain = data.azurerm_cdn_frontdoor_endpoint.shared.host_name
  distribution_record_type   = "CNAME"

  distribution_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.static.id]

  distribution_purge_url = "https://management.azure.com${data.azurerm_cdn_frontdoor_endpoint.shared.id}/purge?api-version=2025-04-15"

  # Purge only this scope's domain: the endpoint is shared with every other
  # scope of the environment.
  distribution_purge_command = "az rest --method post --url '${local.distribution_purge_url}' --body '${jsonencode({ contentPaths = ["/*"], domains = [local.distribution_full_domain] })}'"
}
