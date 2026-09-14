locals {
  distribution_origin_id              = "S3-${var.distribution_bucket_name}"
  distribution_aws_endpoint_url_param = var.distribution_cloudfront_endpoint_url != "" ? "--endpoint-url ${var.distribution_cloudfront_endpoint_url}" : ""

  # Use network_full_domain from network layer (provided via cross-module locals when composed)
  distribution_aliases = local.network_full_domain != "" ? [local.network_full_domain] : []

  # Normalize s3_prefix: trim leading/trailing slashes, then add single leading slash if non-empty
  distribution_s3_prefix_trimmed = trim(var.distribution_s3_prefix, "/")
  distribution_origin_path       = local.distribution_s3_prefix_trimmed != "" ? "/${local.distribution_s3_prefix_trimmed}" : ""

  # ACM certificate domain: derive wildcard from network_domain
  # e.g., "example.com" -> "*.example.com"
  distribution_acm_certificate_domain = local.network_domain != "" ? "*.${local.network_domain}" : ""
  distribution_has_acm_certificate    = length(data.aws_acm_certificate.custom_domain) > 0

  distribution_default_tags = merge(var.distribution_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = "distribution/cloudfront"
  })

  # The WebACL ARN comes from the security layer (null when security=none).
  # Setting/clearing web_acl_id on aws_cloudfront_distribution triggers an
  # in-place update, not a replacement — the distribution ID stays stable.
  distribution_web_acl_arn = local.security_web_acl_arn

  # ---------------------------------------------------------------------------
  # Invocations
  #
  # An invocation arrives as one string naming the kind of function and the
  # event ("Lambda@Edge - viewer request"), which is how the scope
  # configuration asks for it. CloudFront wants them split: Lambda@Edge in
  # lambda_function_association, CloudFront Functions in function_association,
  # each with a dashed event name.
  # ---------------------------------------------------------------------------
  distribution_lambda_kind = "Lambda@Edge"

  distribution_default_lambda_associations = [
    for i in var.distribution_default_behavior.invocations : {
      event_type = replace(trimspace(split(" - ", i.event_type)[1]), " ", "-")
      lambda_arn = i.function_arn
    } if startswith(i.event_type, local.distribution_lambda_kind)
  ]

  distribution_default_function_associations = [
    for i in var.distribution_default_behavior.invocations : {
      event_type   = replace(trimspace(split(" - ", i.event_type)[1]), " ", "-")
      function_arn = i.function_arn
    } if !startswith(i.event_type, local.distribution_lambda_kind)
  ]

  distribution_behavior_lambda_associations = [
    for behavior in var.distribution_behaviors : [
      for i in behavior.invocations : {
        event_type = replace(trimspace(split(" - ", i.event_type)[1]), " ", "-")
        lambda_arn = i.function_arn
      } if startswith(i.event_type, local.distribution_lambda_kind)
    ]
  ]

  distribution_behavior_function_associations = [
    for behavior in var.distribution_behaviors : [
      for i in behavior.invocations : {
        event_type   = replace(trimspace(split(" - ", i.event_type)[1]), " ", "-")
        function_arn = i.function_arn
      } if !startswith(i.event_type, local.distribution_lambda_kind)
    ]
  ]

  # Cross-module references (consumed by network/route53)
  distribution_target_domain  = aws_cloudfront_distribution.static.domain_name
  distribution_target_zone_id = aws_cloudfront_distribution.static.hosted_zone_id
  distribution_record_type    = "A"
}
