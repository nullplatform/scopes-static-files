# =============================================================================
# Test-only locals
#
# This file provides the distribution_* locals that are normally defined by the
# distribution layer (CloudFront, etc.) when modules are composed.
# This file is only used for running isolated unit tests.
#
# NOTE: Files matching test_*.tf are skipped by compose_modules
# =============================================================================

# Test-only variable to allow tests to control the distribution value
variable "distribution_target_domain" {
  description = "Test-only: Target domain from the distribution layer"
  type        = string
  default     = "d1234567890.cloudfront.net"
}

locals {
  # Normally provided by the distribution module (e.g., CloudFront).
  # For testing, we bridge from the variable to the local.
  distribution_target_domain = var.distribution_target_domain
}
