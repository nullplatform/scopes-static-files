# Without this block OpenTofu infers the provider source as
# `hashicorp/nullplatform` and `tofu init` fails with
# "provider registry ... does not have a provider named .../hashicorp/nullplatform".
terraform {
  required_version = ">= 1.6"

  required_providers {
    nullplatform = {
      source = "nullplatform/nullplatform"
    }
  }
}
