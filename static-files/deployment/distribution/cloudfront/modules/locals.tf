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
  # Cache policies
  #
  # Behaviors reference policies by name; a behavior that carries an explicit
  # cache_policy_id skips the lookup. Keys are "default" for the default cache
  # behavior and "behavior-<index>" for each ordered one.
  # ---------------------------------------------------------------------------
  # CachingOptimized is the AWS-recommended default for static content: it caches
  # on the URL alone and leaves compression on.
  distribution_fallback_cache_policy = "Managed-CachingOptimized"

  distribution_cache_policy_names = merge(
    var.distribution_default_behavior.cache_policy_id == null ? {
      default = coalesce(var.distribution_default_behavior.cache_policy, local.distribution_fallback_cache_policy)
    } : {},
    {
      for i, behavior in var.distribution_behaviors : "behavior-${i}" => coalesce(behavior.cache_policy, local.distribution_fallback_cache_policy)
      if behavior.cache_policy_id == null
    }
  )

  distribution_origin_request_policy_names = merge(
    var.distribution_default_behavior.origin_request_policy != null ? {
      default = var.distribution_default_behavior.origin_request_policy
    } : {},
    {
      for i, behavior in var.distribution_behaviors : "behavior-${i}" => behavior.origin_request_policy
      if behavior.origin_request_policy != null
    }
  )

  distribution_response_headers_policy_names = merge(
    var.distribution_default_behavior.response_headers_policy != null ? {
      default = var.distribution_default_behavior.response_headers_policy
    } : {},
    {
      for i, behavior in var.distribution_behaviors : "behavior-${i}" => behavior.response_headers_policy
      if behavior.response_headers_policy != null
    }
  )

  distribution_default_cache_policy_id = (var.distribution_default_behavior.cache_policy_id != null
    ? var.distribution_default_behavior.cache_policy_id
    : try(data.aws_cloudfront_cache_policy.by_name["default"].id, null)
  )

  distribution_behavior_cache_policy_ids = [
    for i, behavior in var.distribution_behaviors : (behavior.cache_policy_id != null
      ? behavior.cache_policy_id
      : try(data.aws_cloudfront_cache_policy.by_name["behavior-${i}"].id, null)
    )
  ]

  # ---------------------------------------------------------------------------
  # Invocations
  #
  # One field per event type in the interface, one association block per
  # non-empty field in the resource.
  # ---------------------------------------------------------------------------
  distribution_default_lambda_associations = [
    for association in [
      { event_type = "viewer-request", lambda_arn = var.distribution_default_behavior.lambda_viewer_request },
      { event_type = "viewer-response", lambda_arn = var.distribution_default_behavior.lambda_viewer_response },
      { event_type = "origin-request", lambda_arn = var.distribution_default_behavior.lambda_origin_request },
      { event_type = "origin-response", lambda_arn = var.distribution_default_behavior.lambda_origin_response },
    ] : association if association.lambda_arn != null
  ]

  distribution_default_function_associations = [
    for association in [
      { event_type = "viewer-request", function_arn = var.distribution_default_behavior.function_viewer_request },
      { event_type = "viewer-response", function_arn = var.distribution_default_behavior.function_viewer_response },
    ] : association if association.function_arn != null
  ]

  distribution_behavior_lambda_associations = [
    for behavior in var.distribution_behaviors : [
      for association in [
        { event_type = "viewer-request", lambda_arn = behavior.lambda_viewer_request },
        { event_type = "viewer-response", lambda_arn = behavior.lambda_viewer_response },
        { event_type = "origin-request", lambda_arn = behavior.lambda_origin_request },
        { event_type = "origin-response", lambda_arn = behavior.lambda_origin_response },
      ] : association if association.lambda_arn != null
    ]
  ]

  distribution_behavior_function_associations = [
    for behavior in var.distribution_behaviors : [
      for association in [
        { event_type = "viewer-request", function_arn = behavior.function_viewer_request },
        { event_type = "viewer-response", function_arn = behavior.function_viewer_response },
      ] : association if association.function_arn != null
    ]
  ]

  # Cross-module references (consumed by network/route53)
  distribution_target_domain  = aws_cloudfront_distribution.static.domain_name
  distribution_target_zone_id = aws_cloudfront_distribution.static.hosted_zone_id
  distribution_record_type    = "A"
}
