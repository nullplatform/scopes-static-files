# =============================================================================
# Test-only locals
#
# This file provides the cross-layer locals that are normally defined by the
# network and security layers when modules are composed.
# Used only for running isolated unit tests on this module.
#
# NOTE: Files matching test_*.tf are skipped by compose_modules
# =============================================================================

# Network layer stubs
variable "network_full_domain" {
  description = "Test-only: Full domain from network layer (e.g., app.example.com)"
  type        = string
  default     = ""
}

variable "network_domain" {
  description = "Test-only: Root domain from network layer (e.g., example.com)"
  type        = string
  default     = ""
}

# Security layer stub: ARN of an attached WebACL, or null when no WAF is in use.
variable "security_web_acl_arn" {
  description = "Test-only: ARN exposed by the security layer (null when security=none)"
  type        = string
  default     = null
}

locals {
  network_full_domain  = var.network_full_domain
  network_domain       = var.network_domain
  security_web_acl_arn = var.security_web_acl_arn
}
