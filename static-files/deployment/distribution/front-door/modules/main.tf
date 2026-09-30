# =============================================================================
# Azure Front Door distribution
#
# Inside a customer-owned profile and endpoint, this scope owns: an origin
# group, an origin (the storage static-website host), a rule set, a route and
# (Task 5) a custom domain with its validation record. Nothing here touches
# the profile or the endpoint themselves.
# =============================================================================

resource "azurerm_cdn_frontdoor_origin_group" "static" {
  name                     = "${var.distribution_app_name}-og"
  cdn_frontdoor_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id

  load_balancing {
    additional_latency_in_milliseconds = 0
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "static" {
  name                          = "${var.distribution_app_name}-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static.id
  enabled                       = true

  host_name                      = data.azurerm_storage_account.static.primary_web_host
  origin_host_header             = data.azurerm_storage_account.static.primary_web_host
  certificate_name_check_enabled = true
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_rule_set" "static" {
  name                     = local.distribution_rule_set_name
  cdn_frontdoor_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id
}

# SPA routing: a request without a file extension (a client-side route) is
# served index.html. Same rule the retired CDN classic layer carried, in Front Door terms.
resource "azurerm_cdn_frontdoor_rule" "spa_fallback" {
  depends_on = [azurerm_cdn_frontdoor_origin_group.static, azurerm_cdn_frontdoor_origin.static]

  name                      = "SpaFallback"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.static.id
  order                     = 1
  behavior_on_match         = "Continue"

  conditions {
    url_file_extension_condition {
      operator     = "LessThan"
      match_values = ["1"]
    }
  }

  actions {
    url_rewrite_action {
      source_pattern          = "/"
      destination             = "/index.html"
      preserve_unmatched_path = false
    }
  }
}

# Long cache for fingerprinted assets under the cached path prefixes (default
# /static/, as the retired CDN classic layer did). Multiple match values are
# OR'ed.
resource "azurerm_cdn_frontdoor_rule" "static_cache" {
  depends_on = [azurerm_cdn_frontdoor_origin_group.static, azurerm_cdn_frontdoor_origin.static]

  name                      = "StaticCache"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.static.id
  order                     = 2
  behavior_on_match         = "Continue"

  conditions {
    url_path_condition {
      operator     = "BeginsWith"
      match_values = var.distribution_cached_path_prefixes
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior = "OverrideAlways"
      cache_duration = "${var.distribution_cache_days}.00:00:00"
      # Azure stores IgnoreQueryString when the override leaves it unset, so an
      # omitted value shows up as a change on every plan. Same value as the route.
      query_string_caching_behavior = "IgnoreQueryString"
    }
  }
}

# Never cache HTML or client routes: every path that starts with none of the
# cached path prefixes (a negated condition over OR'ed values). The purge runs when the route update is
# accepted, but the new origin path reaches the edge minutes later; a request
# in that window re-caches the previous index.html, and the static website
# sends no Cache-Control, so Front Door would keep it for days.
resource "azurerm_cdn_frontdoor_rule" "no_cache_outside_static" {
  depends_on = [azurerm_cdn_frontdoor_origin_group.static, azurerm_cdn_frontdoor_origin.static]

  name                      = "NoCacheOutsideStatic"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.static.id
  order                     = 3
  behavior_on_match         = "Continue"

  conditions {
    url_path_condition {
      operator         = "BeginsWith"
      match_values     = var.distribution_cached_path_prefixes
      negate_condition = true
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior = "Disabled"
    }
  }
}

# Opt-in security headers on every response (no conditions). A rule holds at
# most 5 actions: the four fixed headers plus the optional CSP.
resource "azurerm_cdn_frontdoor_rule" "security_headers" {
  count      = var.distribution_security_headers ? 1 : 0
  depends_on = [azurerm_cdn_frontdoor_origin_group.static, azurerm_cdn_frontdoor_origin.static]

  name                      = "SecurityHeaders"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.static.id
  order                     = 4
  behavior_on_match         = "Continue"

  actions {
    dynamic "response_header_action" {
      for_each = local.distribution_security_headers
      content {
        header_action = "Overwrite"
        header_name   = response_header_action.key
        value         = response_header_action.value
      }
    }

    dynamic "response_header_action" {
      for_each = var.distribution_content_security_policy != "" ? [var.distribution_content_security_policy] : []
      content {
        header_action = "Overwrite"
        header_name   = "Content-Security-Policy"
        value         = response_header_action.value
      }
    }
  }
}

resource "azurerm_cdn_frontdoor_route" "static" {
  name                          = var.distribution_app_name
  cdn_frontdoor_endpoint_id     = data.azurerm_cdn_frontdoor_endpoint.shared.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.static.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.static.id]
  enabled                       = true

  # The version switch: a new deployment changes the origin path and the
  # purge below drops the old content from the edge.
  cdn_frontdoor_origin_path = local.distribution_origin_path

  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  # The endpoint is shared by every scope of the environment, so a route can
  # never own its default hostname. The custom domain is the scope's identity.
  link_to_default_domain          = false
  cdn_frontdoor_custom_domain_ids = local.distribution_custom_domain_ids

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = local.distribution_compressed_content_types
  }
}

# =============================================================================
# Custom domain: mandatory. The route is not reachable through the shared
# endpoint hostname, so without a DNS zone there is nothing to serve.
# =============================================================================
resource "azurerm_cdn_frontdoor_custom_domain" "static" {
  name                     = "${var.distribution_app_name}-domain"
  cdn_frontdoor_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id
  dns_zone_id              = data.azurerm_dns_zone.custom_domain.id
  host_name                = local.distribution_full_domain

  tls {
    certificate_type        = local.distribution_use_customer_certificate ? "CustomerCertificate" : "ManagedCertificate"
    cdn_frontdoor_secret_id = local.distribution_use_customer_certificate ? "${data.azurerm_cdn_frontdoor_profile.shared.id}/secrets/${var.distribution_certificate_secret}" : null
    minimum_tls_version     = "TLS12"
  }

  lifecycle {
    precondition {
      condition     = local.distribution_has_custom_domain
      error_message = "The front-door distribution needs a custom domain: configure the network layer (network.azure_network = azure_dns with a DNS zone) for this scope."
    }
  }
}

# The validation token read back from Azure once the custom domain is applied.
# The resource's own attribute is not enough when an existing domain switches
# from a customer certificate to a managed one: its token is "" in state and
# the provider only fills it after the update, so the TXT record would be
# planned with an empty value and rejected. A data source that depends on the
# domain is read after the domain's changes are applied (at plan time when
# the domain is unchanged, so steady deployments show no diff).
data "azurerm_cdn_frontdoor_custom_domain" "static" {
  count = local.distribution_use_customer_certificate ? 0 : 1

  name                = azurerm_cdn_frontdoor_custom_domain.static.name
  profile_name        = var.distribution_front_door_profile
  resource_group_name = var.distribution_front_door_resource_group

  depends_on = [azurerm_cdn_frontdoor_custom_domain.static]
}

# Front Door proves domain ownership through _dnsauth.<subdomain> holding the
# validation token. The managed certificate is issued once this resolves.
# Not needed with a customer certificate: its CN/SAN proves ownership.
resource "azurerm_dns_txt_record" "custom_domain_validation" {
  count = local.distribution_use_customer_certificate ? 0 : 1

  name                = "_dnsauth.${var.network_subdomain}"
  zone_name           = var.network_dns_zone_name
  resource_group_name = var.network_dns_zone_resource_group
  ttl                 = 3600

  record {
    value = data.azurerm_cdn_frontdoor_custom_domain.static[0].validation_token
  }
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "static" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.static.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.static.id]
}

# Drop the previous version from the edge whenever the origin path changes.
# Same role as the CloudFront invalidation, scoped to this domain because the
# endpoint is shared.
resource "terraform_data" "front_door_purge" {
  triggers_replace = [
    local.distribution_origin_path
  ]

  provisioner "local-exec" {
    command = local.distribution_purge_command
  }

  depends_on = [
    azurerm_cdn_frontdoor_route.static,
    azurerm_cdn_frontdoor_custom_domain_association.static,
  ]
}
