locals {
  # Exposed to other layers (e.g., distribution/cloudfront) via the composed root.
  # The value is the WebACL ARN that downstream modules can plug into resources
  # like aws_cloudfront_distribution.web_acl_id.
  security_web_acl_arn = data.aws_wafv2_web_acl.cloudfront.arn
}
