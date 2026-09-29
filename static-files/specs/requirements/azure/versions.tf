terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Consumed by infra layers on azurerm 4.x and by stacks still on 3.x:
      # only arguments whose names are identical in 3.117 and 4.x are used.
      version = ">= 3.117, < 5.0"
    }
  }
}
