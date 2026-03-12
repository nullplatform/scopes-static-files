# =============================================================================
# Unit tests for distribution/static-web-apps module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_resource "azurerm_static_web_app" {
    defaults = {
      id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-resource-group/providers/Microsoft.Web/staticSites/my-app-prod"
      default_host_name = "my-app-prod.azurestaticapps.net"
      api_key           = "mock-api-key"
    }
  }
}

mock_provider "null" {}

variables {
  distribution_app_name           = "my-app-prod"
  distribution_sku_tier           = "Free"
  distribution_location           = "eastus2"
  distribution_artifact_url       = "https://mystaticstorage.blob.core.windows.net/artifacts/app.zip"
  distribution_artifact_dir       = "/tmp/artifacts/app"
  distribution_resource_tags_json = {
    Environment = "production"
    Application = "my-app"
  }
  network_full_domain = ""
  network_domain      = ""
  azure_provider = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = "my-resource-group"
    storage_account = "mytfstatestorage"
    container       = "tfstate"
  }
}

# =============================================================================
# Test: Static Web App is created with correct properties
# =============================================================================
run "creates_static_web_app" {
  command = plan

  assert {
    condition     = azurerm_static_web_app.main.name == "my-app-prod"
    error_message = "Static Web App name should be 'my-app-prod'"
  }

  assert {
    condition     = azurerm_static_web_app.main.location == "eastus2"
    error_message = "Static Web App location should be 'eastus2'"
  }

  assert {
    condition     = azurerm_static_web_app.main.resource_group_name == "my-resource-group"
    error_message = "Static Web App should be in 'my-resource-group'"
  }

  assert {
    condition     = azurerm_static_web_app.main.sku_tier == "Free"
    error_message = "Static Web App SKU tier should be 'Free'"
  }

  assert {
    condition     = azurerm_static_web_app.main.sku_size == "Free"
    error_message = "Static Web App SKU size should match SKU tier 'Free'"
  }
}

# =============================================================================
# Test: Static Web App with Standard SKU
# =============================================================================
run "creates_static_web_app_standard_sku" {
  command = plan

  variables {
    distribution_sku_tier = "Standard"
  }

  assert {
    condition     = azurerm_static_web_app.main.sku_tier == "Standard"
    error_message = "Static Web App SKU tier should be 'Standard'"
  }

  assert {
    condition     = azurerm_static_web_app.main.sku_size == "Standard"
    error_message = "Static Web App SKU size should match SKU tier 'Standard'"
  }
}

# =============================================================================
# Test: No custom domain without network_full_domain
# =============================================================================
run "no_custom_domain_without_network_domain" {
  command = plan

  assert {
    condition     = local.distribution_has_custom_domain == false
    error_message = "Should not have custom domain when network_full_domain is empty"
  }

  assert {
    condition     = length(azurerm_static_web_app_custom_domain.main) == 0
    error_message = "Should not create custom domain resource when network_full_domain is empty"
  }
}

# =============================================================================
# Test: Custom domain with network_full_domain
# =============================================================================
run "has_custom_domain_with_network_domain" {
  command = plan

  variables {
    network_full_domain = "app.example.com"
  }

  assert {
    condition     = local.distribution_has_custom_domain == true
    error_message = "Should have custom domain when network_full_domain is set"
  }

  assert {
    condition     = length(azurerm_static_web_app_custom_domain.main) == 1
    error_message = "Should create custom domain resource when network_full_domain is set"
  }

  assert {
    condition     = azurerm_static_web_app_custom_domain.main[0].domain_name == "app.example.com"
    error_message = "Custom domain name should be 'app.example.com'"
  }

  assert {
    condition     = azurerm_static_web_app_custom_domain.main[0].validation_type == "cname-delegation"
    error_message = "Custom domain validation type should be 'cname-delegation'"
  }
}

# =============================================================================
# Test: Cross-module locals for DNS integration
# =============================================================================
run "cross_module_locals_for_dns" {
  command = plan

  assert {
    condition     = local.distribution_record_type == "CNAME"
    error_message = "Record type should be 'CNAME' for Azure Static Web Apps"
  }
}

# =============================================================================
# Test: DNS-related outputs
# =============================================================================
run "dns_related_outputs" {
  command = plan

  assert {
    condition     = output.distribution_record_type == "CNAME"
    error_message = "distribution_record_type should be 'CNAME'"
  }
}

# =============================================================================
# Test: Website URL without network domain
# =============================================================================
run "website_url_without_network_domain" {
  command = plan

  assert {
    condition     = startswith(output.distribution_website_url, "https://")
    error_message = "distribution_website_url should start with 'https://'"
  }
}

# =============================================================================
# Test: Website URL with network domain
# =============================================================================
run "website_url_with_network_domain" {
  command = plan

  variables {
    network_full_domain = "app.example.com"
  }

  assert {
    condition     = output.distribution_website_url == "https://app.example.com"
    error_message = "distribution_website_url should be 'https://app.example.com'"
  }
}

# =============================================================================
# Test: Resource tags include module metadata
# =============================================================================
run "resource_tags_include_module" {
  command = plan

  assert {
    condition     = azurerm_static_web_app.main.tags["ManagedBy"] == "terraform"
    error_message = "Tags should include ManagedBy = 'terraform'"
  }

  assert {
    condition     = azurerm_static_web_app.main.tags["Module"] == "distribution/static-web-apps"
    error_message = "Tags should include Module = 'distribution/static-web-apps'"
  }

  assert {
    condition     = azurerm_static_web_app.main.tags["Environment"] == "production"
    error_message = "Tags should include custom tag Environment = 'production'"
  }

  assert {
    condition     = azurerm_static_web_app.main.tags["Application"] == "my-app"
    error_message = "Tags should include custom tag Application = 'my-app'"
  }
}

# =============================================================================
# Test: Deploy triggers on artifact URL
# =============================================================================
run "deploy_triggers_on_artifact_url" {
  command = plan

  assert {
    condition     = null_resource.deploy_content.triggers.artifact_url == "https://mystaticstorage.blob.core.windows.net/artifacts/app.zip"
    error_message = "Deploy trigger artifact_url should match the distribution_artifact_url variable"
  }
}
