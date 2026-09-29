# =============================================================================
# Unit tests for distribution/front-door module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_storage_account" {
    defaults = {
      primary_web_host = "mystaticstorage.z13.web.core.windows.net"
    }
  }

  mock_data "azurerm_cdn_frontdoor_profile" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd"
      sku_name = "Standard_AzureFrontDoor"
    }
  }

  mock_data "azurerm_cdn_frontdoor_endpoint" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/afdEndpoints/shared-endpoint"
      host_name = "shared-endpoint-abcd.z01.azurefd.net"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_origin_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/originGroups/mock-og"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_origin" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/originGroups/mock-og/origins/mock-origin"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_rule_set" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/ruleSets/mockruleset"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_custom_domain" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/customDomains/mock-domain"
      validation_token = "mock-validation-token"
    }
  }

  mock_resource "azurerm_cdn_frontdoor_route" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/afdEndpoints/shared-endpoint/routes/mock-route"
    }
  }

  mock_data "azurerm_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnsZones/example.com"
    }
  }
}

variables {
  distribution_storage_account           = "mystaticstorage"
  distribution_container_name            = "$web"
  distribution_blob_prefix               = "frontends/4/612605537"
  distribution_app_name                  = "automation-development-tools-7"
  distribution_front_door_profile        = "shared-afd"
  distribution_front_door_endpoint       = "shared-endpoint"
  distribution_front_door_resource_group = "cdn-rg"
  distribution_resource_tags_json = {
    Environment = "production"
  }
  network_full_domain             = "automation-development-tools.example.com"
  network_domain                  = "example.com"
  network_subdomain               = "automation-development-tools"
  network_dns_zone_name           = "example.com"
  network_dns_zone_resource_group = "dns-rg"
  azure_provider = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = "my-resource-group"
    storage_account = "mytfstatestorage"
    container       = "tfstate"
  }
}

run "origin_points_to_static_website_host" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_origin.static.host_name == "mystaticstorage.z13.web.core.windows.net"
    error_message = "Origin host should be the storage account static-website host"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_origin.static.origin_host_header == "mystaticstorage.z13.web.core.windows.net"
    error_message = "Origin host header should match the origin host"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.static.name == "automation-development-tools-7-og"
    error_message = "Origin group name should be '<app_name>-og'"
  }
}

run "route_uses_origin_path_and_custom_domain_only" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.cdn_frontdoor_origin_path == "/frontends/4/612605537"
    error_message = "Route origin path should be the normalized blob prefix"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.link_to_default_domain == false
    error_message = "Route must not be linked to the shared endpoint's default domain"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.https_redirect_enabled == true
    error_message = "Route should redirect HTTP to HTTPS"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.forwarding_protocol == "HttpsOnly"
    error_message = "Route should forward to the origin over HTTPS only"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_route.static.cache).compression_enabled == true
    error_message = "Route cache should enable compression"
  }
}

run "origin_path_normalizes_leading_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "/app"
  }

  assert {
    condition     = local.distribution_origin_path == "/app"
    error_message = "Origin path should be '/app'"
  }
}

run "origin_path_handles_empty" {
  command = plan

  variables {
    distribution_blob_prefix = ""
  }

  assert {
    condition     = local.distribution_origin_path == ""
    error_message = "Origin path should be empty when prefix is empty"
  }
}

run "origin_path_trims_trailing_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "/app/subfolder/"
  }

  assert {
    condition     = local.distribution_origin_path == "/app/subfolder"
    error_message = "Origin path should trim trailing slashes"
  }
}

run "rule_set_name_is_alphanumeric_and_short" {
  command = plan

  variables {
    distribution_app_name = "very-long-application-slug-with-many-words-and-a-long-scope-name-123456"
  }

  assert {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,59}$", azurerm_cdn_frontdoor_rule_set.static.name))
    error_message = "Rule set name must be letters and digits only, at most 60 chars, got '${azurerm_cdn_frontdoor_rule_set.static.name}'"
  }
}

run "spa_fallback_rule_rewrites_to_index" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_rule.spa_fallback.order == 1
    error_message = "SPA fallback should be the first rule"
  }

  assert {
    condition     = one(one(azurerm_cdn_frontdoor_rule.spa_fallback.actions).url_rewrite_action).destination == "/index.html"
    error_message = "SPA fallback should rewrite to /index.html"
  }
}

run "cross_module_locals_for_dns" {
  command = plan

  assert {
    condition     = local.distribution_record_type == "CNAME"
    error_message = "Record type should be CNAME"
  }

  assert {
    condition     = local.distribution_target_domain == "shared-endpoint-abcd.z01.azurefd.net"
    error_message = "DNS target should be the shared endpoint hostname"
  }
}

run "website_url_is_the_custom_domain" {
  command = plan

  assert {
    condition     = output.distribution_website_url == "https://automation-development-tools.example.com"
    error_message = "Website URL should be the custom domain"
  }
}

run "custom_domain_with_managed_certificate" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_custom_domain.static.host_name == "automation-development-tools.example.com"
    error_message = "Custom domain host should be the network full domain"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_custom_domain.static.tls).certificate_type == "ManagedCertificate"
    error_message = "Custom domain should use a managed certificate"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_custom_domain.static.tls).minimum_tls_version == "TLS12"
    error_message = "Custom domain should require TLS 1.2"
  }
}

run "validation_txt_record_in_dns_zone_resource_group" {
  command = plan

  assert {
    condition     = azurerm_dns_txt_record.custom_domain_validation.name == "_dnsauth.automation-development-tools"
    error_message = "Validation record should be _dnsauth.<subdomain>"
  }

  assert {
    condition     = azurerm_dns_txt_record.custom_domain_validation.zone_name == "example.com"
    error_message = "Validation record should live in the network DNS zone"
  }

  assert {
    condition     = azurerm_dns_txt_record.custom_domain_validation.resource_group_name == "dns-rg"
    error_message = "Validation record should be created in the DNS zone resource group"
  }
}

run "route_is_associated_with_the_custom_domain" {
  command = plan

  assert {
    condition     = length(azurerm_cdn_frontdoor_route.static.cdn_frontdoor_custom_domain_ids) == 1
    error_message = "Route should reference exactly one custom domain"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_custom_domain_association.static.cdn_frontdoor_route_ids) == 1
    error_message = "Association should reference the scope's route"
  }
}

run "purge_is_scoped_to_the_custom_domain" {
  command = plan

  assert {
    condition     = strcontains(local.distribution_purge_command, "afdEndpoints/shared-endpoint/purge?api-version=2025-04-15")
    error_message = "Purge should target the shared endpoint purge action"
  }

  assert {
    condition     = strcontains(local.distribution_purge_command, "\"domains\":[\"automation-development-tools.example.com\"]")
    error_message = "Purge should be filtered by this scope's domain"
  }

  assert {
    condition     = terraform_data.front_door_purge.triggers_replace[0] == "/frontends/4/612605537"
    error_message = "Purge should re-run when the origin path changes"
  }
}

run "fails_without_custom_domain" {
  command = plan

  variables {
    network_full_domain = ""
    network_subdomain   = ""
  }

  expect_failures = [
    azurerm_cdn_frontdoor_custom_domain.static,
  ]
}
