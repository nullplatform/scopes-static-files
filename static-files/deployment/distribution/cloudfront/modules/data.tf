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

# Managed cache and origin request policies, looked up by name. Only the names
# the variables accept are ever requested, and only when a behavior asks for the
# policy model — a legacy-only distribution reads neither.
data "aws_cloudfront_cache_policy" "managed" {
  for_each = local.distribution_requested_cache_policies
  name     = "Managed-${each.key}"
}

data "aws_cloudfront_origin_request_policy" "managed" {
  for_each = local.distribution_requested_origin_request_policies
  name     = "Managed-${each.key}"
}

data "aws_cloudfront_response_headers_policy" "managed" {
  for_each = local.distribution_requested_response_headers_policies
  name     = "Managed-${each.key}"
}
