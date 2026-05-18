data "aws_s3_bucket" "static" {
  bucket = var.distribution_bucket_name
}

# Look up ACM certificate for custom domain (must be in us-east-1 for CloudFront)
# Uses wildcard pattern: *.parent-domain.tld
# Note: PENDING_VALIDATION is included for LocalStack compatibility in integration tests
data "aws_acm_certificate" "custom_domain" {
  count = local.distribution_acm_certificate_domain != "" ? 1 : 0

  provider    = aws.us_east_1
  domain      = local.distribution_acm_certificate_domain
  statuses    = ["ISSUED", "PENDING_VALIDATION"]
  most_recent = true
}

# Look up existing WAFv2 WebACL to attach to the distribution.
# WebACLs with scope=CLOUDFRONT only exist in us-east-1.
data "aws_wafv2_web_acl" "cloudfront" {
  count = var.distribution_web_acl_name != "" ? 1 : 0

  provider = aws.us_east_1
  name     = var.distribution_web_acl_name
  scope    = "CLOUDFRONT"
}