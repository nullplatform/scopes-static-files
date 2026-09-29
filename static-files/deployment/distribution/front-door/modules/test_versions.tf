# =============================================================================
# Test-only provider pin
#
# compose_modules skips test_*.tf, so this never reaches a composed root
# module (provider/azure/modules/provider.tf owns the constraint there).
# `tofu test` on this directory alone would otherwise resolve the newest
# azurerm, whose 4.x/5.x schemas differ from the 3.x one the modules target.
# =============================================================================
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.117, < 4.0"
    }
  }
}
