terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.15 is the first release with an identity block on
      # azurerm_cdn_frontdoor_profile, which the customer certificate needs.
      version = ">= 4.15, < 5.0"
    }
  }
}
