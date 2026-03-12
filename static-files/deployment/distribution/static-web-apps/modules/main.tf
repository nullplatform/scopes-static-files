# =============================================================================
# Azure Static Web App Distribution
#
# Creates an Azure Static Web App for static website hosting and deploys
# content using the SWA CLI via a local-exec provisioner.
# =============================================================================

# Static Web App
resource "azurerm_static_web_app" "main" {
  name                = var.distribution_app_name
  location            = var.distribution_location
  resource_group_name = var.azure_provider.resource_group
  sku_tier            = var.distribution_sku_tier
  sku_size            = var.distribution_sku_tier

  tags = local.distribution_tags
}

# Custom domain configuration (when network layer provides domain)
resource "azurerm_static_web_app_custom_domain" "main" {
  count = local.distribution_has_custom_domain ? 1 : 0

  static_web_app_id = azurerm_static_web_app.main.id
  domain_name       = local.distribution_full_domain
  validation_type   = "cname-delegation"
}

# Deploy static content to the Static Web App
resource "null_resource" "deploy_content" {
  triggers = {
    artifact_url = var.distribution_artifact_url
    app_id       = azurerm_static_web_app.main.id
  }

  provisioner "local-exec" {
    command = "${path.module}/../deploy_content"

    environment = {
      SWA_DEPLOYMENT_TOKEN = azurerm_static_web_app.main.api_key
      ARTIFACT_DIR         = var.distribution_artifact_dir
    }
  }

  depends_on = [azurerm_static_web_app.main]
}
