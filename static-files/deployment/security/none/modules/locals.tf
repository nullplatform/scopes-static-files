locals {
  # No WAF attached. Defined here so downstream layers (e.g., distribution)
  # can reference local.security_web_acl_arn unconditionally — the value is
  # null when no security layer is configured.
  security_web_acl_arn = null
}
