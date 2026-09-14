resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${var.distribution_app_name}-oac"
  description                       = "OAC for ${var.distribution_app_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.distribution_default_root_object
  aliases             = local.distribution_aliases
  price_class         = var.distribution_price_class
  comment             = "Distribution for ${var.distribution_app_name}"
  web_acl_id          = local.distribution_web_acl_arn

  origin {
    domain_name              = data.aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = local.distribution_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id

    origin_path = local.distribution_origin_path
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.distribution_origin_id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = var.distribution_default_behavior.viewer_protocol_policy
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = var.distribution_default_behavior.compress

    dynamic "lambda_function_association" {
      for_each = local.distribution_default_lambda_associations
      content {
        event_type = lambda_function_association.value.event_type
        lambda_arn = lambda_function_association.value.lambda_arn
      }
    }

    dynamic "function_association" {
      for_each = local.distribution_default_function_associations
      content {
        event_type   = function_association.value.event_type
        function_arn = function_association.value.function_arn
      }
    }
  }

  # The list order is the CloudFront precedence: the first pattern that matches
  # a request wins, so iterating a list (never a map or a set) matters here.
  dynamic "ordered_cache_behavior" {
    for_each = var.distribution_behaviors

    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = local.distribution_origin_id

      forwarded_values {
        query_string = false
        cookies {
          forward = "none"
        }
      }

      viewer_protocol_policy = ordered_cache_behavior.value.viewer_protocol_policy
      min_ttl                = 0
      default_ttl            = 3600
      max_ttl                = 86400
      compress               = ordered_cache_behavior.value.compress

      dynamic "lambda_function_association" {
        for_each = local.distribution_behavior_lambda_associations[ordered_cache_behavior.key]
        content {
          event_type = lambda_function_association.value.event_type
          lambda_arn = lambda_function_association.value.lambda_arn
        }
      }

      dynamic "function_association" {
        for_each = local.distribution_behavior_function_associations[ordered_cache_behavior.key]
        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.function_arn
        }
      }
    }
  }

  dynamic "custom_error_response" {
    for_each = var.distribution_custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.distribution_geo_restriction.restriction_type
      locations        = var.distribution_geo_restriction.locations
    }
  }

  # Use ACM certificate if available for custom domain, otherwise use default CloudFront certificate
  dynamic "viewer_certificate" {
    for_each = local.distribution_has_acm_certificate ? [1] : []
    content {
      acm_certificate_arn      = data.aws_acm_certificate.custom_domain[0].arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.distribution_has_acm_certificate ? [] : [1]
    content {
      cloudfront_default_certificate = true
      minimum_protocol_version       = "TLSv1.2_2021"
    }
  }

  tags = local.distribution_default_tags
}

# Invalidate CloudFront cache on every deployment (when origin path changes)
resource "terraform_data" "cloudfront_invalidation" {
  # Trigger invalidation whenever the origin path changes
  triggers_replace = [
    local.distribution_origin_path
  ]

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation ${local.distribution_aws_endpoint_url_param} --distribution-id ${aws_cloudfront_distribution.static.id} --paths '/*'"
  }

  depends_on = [aws_cloudfront_distribution.static]
}
