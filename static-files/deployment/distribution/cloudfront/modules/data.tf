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

# Cache policies referenced by name (managed policies included). A behavior that
# carries an explicit *_policy_id skips its lookup.
data "aws_cloudfront_cache_policy" "by_name" {
  for_each = local.distribution_cache_policy_names

  name = each.value
}

data "aws_cloudfront_origin_request_policy" "by_name" {
  for_each = local.distribution_origin_request_policy_names

  name = each.value
}

data "aws_cloudfront_response_headers_policy" "by_name" {
  for_each = local.distribution_response_headers_policy_names

  name = each.value
}
