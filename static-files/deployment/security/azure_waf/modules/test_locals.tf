# =============================================================================
# Test-only locals and variables
#
# Bridges what the composed root module gets from distribution/front-door:
# the distribution_app_name variable and the distribution_front_door_profile_id
# and distribution_custom_domain_id locals. Skipped by compose_modules
# (test_*.tf).
# =============================================================================

variable "distribution_app_name" {
  description = "Test-only: base name the distribution layer gives every resource (<app>-<scope>-<id>)"
  type        = string
}

variable "distribution_front_door_profile_id" {
  description = "Test-only: id of the shared Front Door profile"
  type        = string
}

variable "distribution_custom_domain_id" {
  description = "Test-only: id of the scope's Front Door custom domain"
  type        = string
}

locals {
  distribution_front_door_profile_id = var.distribution_front_door_profile_id
  distribution_custom_domain_id      = var.distribution_custom_domain_id
}
