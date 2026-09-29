locals {
  distribution_full_domain       = local.network_full_domain
  distribution_has_custom_domain = local.network_full_domain != ""

  distribution_blob_prefix_trimmed = trim(var.distribution_blob_prefix, "/")
  distribution_origin_path         = local.distribution_blob_prefix_trimmed != "" ? "/${local.distribution_blob_prefix_trimmed}" : ""

  # Rule set names only accept letters and digits, must start with a letter and
  # have at most 60 chars. "<app>-<scope>-<id>" is split so the id (last
  # segment) survives truncation.
  distribution_name_parts  = split("-", var.distribution_app_name)
  distribution_scope_id    = element(local.distribution_name_parts, length(local.distribution_name_parts) - 1)
  distribution_name_prefix = replace(join("", slice(local.distribution_name_parts, 0, length(local.distribution_name_parts) - 1)), "/[^A-Za-z0-9]/", "")
  # "rs" guarantees a leading letter; the scope id at the end guarantees
  # uniqueness inside the shared profile; 60 is Azure's limit.
  distribution_rule_set_name = "rs${substr(local.distribution_name_prefix, 0, 58 - length(local.distribution_scope_id))}${local.distribution_scope_id}"

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

  # Fixed values for the SecurityHeaders rule. The CSP is appended only when
  # configured: a wrong policy breaks the site, so there is no default one.
  distribution_security_headers = {
    "Strict-Transport-Security" = "max-age=31536000; includeSubDomains"
    "X-Content-Type-Options"    = "nosniff"
    "X-Frame-Options"           = "SAMEORIGIN"
    "Referrer-Policy"           = "strict-origin-when-cross-origin"
  }

  # Cross-module references (consumed by network/azure_dns): the CNAME points
  # at the shared endpoint; Front Door then routes by Host header.
  distribution_target_domain = data.azurerm_cdn_frontdoor_endpoint.shared.host_name
  distribution_record_type   = "CNAME"

  distribution_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.static.id]

  # Cross-module references (consumed by security/azure_waf): the security
  # policy lives in the shared profile and covers this scope's domain only.
  distribution_front_door_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id
  distribution_custom_domain_id      = azurerm_cdn_frontdoor_custom_domain.static.id

  distribution_purge_url = "https://management.azure.com${data.azurerm_cdn_frontdoor_endpoint.shared.id}/purge?api-version=2025-04-15"

  # Purge only this scope's domain: the endpoint is shared with every other
  # scope of the environment.
  distribution_purge_command = "az rest --method post --url '${local.distribution_purge_url}' --body '${jsonencode({ contentPaths = ["/*"], domains = [local.distribution_full_domain] })}'"
}
