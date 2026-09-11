# =============================================================================
# Unit tests for distribution/cloudfront module
#
# Run: tofu test
# =============================================================================

mock_provider "aws" {
  mock_data "aws_s3_bucket" {
    defaults = {
      id                          = "my-static-bucket"
      arn                         = "arn:aws:s3:::my-static-bucket"
      bucket_regional_domain_name = "my-static-bucket.s3.us-east-1.amazonaws.com"
    }
  }
}

# ACM certificates for CloudFront must be in us-east-1
mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      id  = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    }
  }
}

variables {
  distribution_bucket_name = "my-static-bucket"
  distribution_s3_prefix   = "app/scope-1"
  distribution_app_name    = "my-app-prod"
  network_full_domain      = ""
  network_domain           = ""
  distribution_resource_tags_json = {
    Environment = "production"
    Application = "my-app"
  }
}

# =============================================================================
# Test: Origin Access Control is created
# =============================================================================
run "creates_origin_access_control" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.static.name == "my-app-prod-oac"
    error_message = "OAC name should be 'my-app-prod-oac'"
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.static.origin_access_control_origin_type == "s3"
    error_message = "OAC origin type should be 's3'"
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.static.signing_behavior == "always"
    error_message = "OAC signing behavior should be 'always'"
  }
}

# =============================================================================
# Test: CloudFront distribution basic configuration
# =============================================================================
run "distribution_basic_configuration" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.static.enabled == true
    error_message = "Distribution should be enabled"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.is_ipv6_enabled == true
    error_message = "IPv6 should be enabled"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_root_object == "index.html"
    error_message = "Default root object should be 'index.html'"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.price_class == "PriceClass_100"
    error_message = "Price class should be 'PriceClass_100'"
  }
}

# =============================================================================
# Test: Distribution has no aliases when network_full_domain is empty
# =============================================================================
run "no_aliases_without_network_domain" {
  command = plan

  assert {
    condition     = length(local.distribution_aliases) == 0
    error_message = "Should have no aliases when network_full_domain is empty"
  }
}

# =============================================================================
# Test: Distribution has alias when network_full_domain is set
# =============================================================================
run "has_alias_with_network_domain" {
  command = plan

  variables {
    network_full_domain = "cdn.example.com"
  }

  assert {
    condition     = length(local.distribution_aliases) == 1
    error_message = "Should have one alias when network_full_domain is set"
  }

  assert {
    condition     = local.distribution_aliases[0] == "cdn.example.com"
    error_message = "Alias should be 'cdn.example.com'"
  }
}

# =============================================================================
# Test: Origin ID is computed correctly
# =============================================================================
run "origin_id_format" {
  command = plan

  assert {
    condition     = local.distribution_origin_id == "S3-my-static-bucket"
    error_message = "Origin ID should be 'S3-my-static-bucket'"
  }
}

# =============================================================================
# Test: Origin path normalization - removes double slashes
# =============================================================================
run "origin_path_normalizes_leading_slash" {
  command = plan

  variables {
    distribution_s3_prefix = "/app"
  }

  assert {
    condition     = local.distribution_origin_path == "/app"
    error_message = "Origin path should be '/app' not '//app'"
  }
}

# =============================================================================
# Test: Origin path normalization - adds leading slash if missing
# =============================================================================
run "origin_path_adds_leading_slash" {
  command = plan

  variables {
    distribution_s3_prefix = "app"
  }

  assert {
    condition     = local.distribution_origin_path == "/app"
    error_message = "Origin path should add leading slash"
  }
}

# =============================================================================
# Test: Origin path normalization - handles empty prefix
# =============================================================================
run "origin_path_handles_empty" {
  command = plan

  variables {
    distribution_s3_prefix = ""
  }

  assert {
    condition     = local.distribution_origin_path == ""
    error_message = "Origin path should be empty when prefix is empty"
  }
}

# =============================================================================
# Test: Origin path normalization - trims trailing slashes
# =============================================================================
run "origin_path_trims_trailing_slash" {
  command = plan

  variables {
    distribution_s3_prefix = "/app/subfolder/"
  }

  assert {
    condition     = local.distribution_origin_path == "/app/subfolder"
    error_message = "Origin path should trim trailing slashes"
  }
}

# =============================================================================
# Test: Default tags include module tag
# =============================================================================
run "default_tags_include_module" {
  command = plan

  assert {
    condition     = local.distribution_default_tags["ManagedBy"] == "terraform"
    error_message = "Tags should include ManagedBy=terraform"
  }

  assert {
    condition     = local.distribution_default_tags["Module"] == "distribution/cloudfront"
    error_message = "Tags should include Module=distribution/cloudfront"
  }

  assert {
    condition     = local.distribution_default_tags["Environment"] == "production"
    error_message = "Tags should preserve input Environment tag"
  }
}

# =============================================================================
# Test: Cross-module locals for DNS integration
# =============================================================================
run "cross_module_locals_for_dns" {
  command = plan

  assert {
    condition     = local.distribution_record_type == "A"
    error_message = "Record type should be 'A' for CloudFront alias records"
  }
}

# =============================================================================
# Test: Default behavior caching is fixed, not configurable
#
# Caching is what the scope has always done: nothing forwarded to the origin
# and the same TTLs. Only the viewer protocol, compression and the invocations
# are left to configure.
# =============================================================================
run "default_behavior_caching_is_fixed" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].min_ttl == 0
    error_message = "Default behavior should keep its min TTL at 0"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].default_ttl == 3600
    error_message = "Default behavior should keep its default TTL at 3600"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].max_ttl == 86400
    error_message = "Default behavior should keep its max TTL at 86400"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.static.default_cache_behavior[0].forwarded_values).query_string == false
    error_message = "Default behavior should not forward query strings"
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.static.default_cache_behavior[0].forwarded_values).cookies).forward == "none"
    error_message = "Default behavior should not forward cookies"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].allowed_methods == toset(["GET", "HEAD", "OPTIONS"])
    error_message = "Default behavior should allow GET, HEAD and OPTIONS"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].cached_methods == toset(["GET", "HEAD"])
    error_message = "Default behavior should cache GET and HEAD"
  }
}

# =============================================================================
# Test: Default behavior viewer settings
# =============================================================================
run "default_behavior_viewer_settings" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Default behavior should redirect to HTTPS"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].compress == true
    error_message = "Default behavior should compress by default"
  }
}

run "default_behavior_viewer_settings_are_configurable" {
  command = plan

  variables {
    distribution_default_behavior = {
      viewer_protocol_policy = "https-only"
      compress               = false
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].viewer_protocol_policy == "https-only"
    error_message = "Viewer protocol policy should be configurable"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].compress == false
    error_message = "Compression should be configurable"
  }
}

# =============================================================================
# Test: No ordered cache behaviors unless configured
# =============================================================================
run "no_ordered_behaviors_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior) == 0
    error_message = "Should create no ordered cache behaviors when none are configured"
  }
}

# =============================================================================
# Test: No invocations unless configured
# =============================================================================
run "no_invocations_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].lambda_function_association) == 0
    error_message = "Default behavior should have no Lambda@Edge associations when none are configured"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].function_association) == 0
    error_message = "Default behavior should have no CloudFront Function associations when none are configured"
  }
}

# =============================================================================
# Test: An invocation names both the kind of function and the event
#
# The scope configuration offers one dropdown pairing them, so the module reads
# which association block to write from the same string.
# =============================================================================
run "invocations_split_into_lambda_and_function_associations" {
  command = plan

  variables {
    distribution_default_behavior = {
      invocations = [
        { event_type = "Lambda@Edge - viewer request", function_arn = "arn:aws:lambda:us-east-1:123456789012:function:auth:1" },
        { event_type = "Lambda@Edge - origin response", function_arn = "arn:aws:lambda:us-east-1:123456789012:function:headers:2" },
        { event_type = "CloudFront Function - viewer response", function_arn = "arn:aws:cloudfront::123456789012:function/rewrite" },
      ]
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].lambda_function_association) == 2
    error_message = "The two Lambda@Edge invocations should become Lambda@Edge associations"
  }

  assert {
    condition = length([
      for a in aws_cloudfront_distribution.static.default_cache_behavior[0].lambda_function_association :
      a if a.event_type == "viewer-request" && a.lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:auth:1"
    ]) == 1
    error_message = "Should translate 'Lambda@Edge - viewer request' into a viewer-request association"
  }

  assert {
    condition = length([
      for a in aws_cloudfront_distribution.static.default_cache_behavior[0].lambda_function_association :
      a if a.event_type == "origin-response" && a.lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:headers:2"
    ]) == 1
    error_message = "Should translate 'Lambda@Edge - origin response' into an origin-response association"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].function_association) == 1
    error_message = "The CloudFront Function invocation should become a function association"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.static.default_cache_behavior[0].function_association).event_type == "viewer-response"
    error_message = "Should translate 'CloudFront Function - viewer response' into a viewer-response association"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.static.default_cache_behavior[0].function_association).function_arn == "arn:aws:cloudfront::123456789012:function/rewrite"
    error_message = "The CloudFront Function association should carry its ARN"
  }
}

# =============================================================================
# Test: Ordered behaviors are created in the configured order
# =============================================================================
run "ordered_behaviors_keep_their_order" {
  command = plan

  variables {
    distribution_behaviors = [
      { path_pattern = "/api/*" },
      { path_pattern = "/static/*" },
      { path_pattern = "/assets/*" }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior) == 3
    error_message = "Should create one ordered cache behavior per configured behavior"
  }

  assert {
    condition = [
      for b in aws_cloudfront_distribution.static.ordered_cache_behavior : b.path_pattern
    ] == ["/api/*", "/static/*", "/assets/*"]
    error_message = "Ordered behaviors must keep the configured order: it is the CloudFront precedence"
  }
}

# =============================================================================
# Test: Each ordered behavior carries its own invocations and viewer settings
# =============================================================================
run "ordered_behaviors_carry_their_own_settings" {
  command = plan

  variables {
    distribution_behaviors = [
      {
        path_pattern           = "/api/*"
        viewer_protocol_policy = "https-only"
        compress               = false
        invocations = [
          { event_type = "Lambda@Edge - viewer request", function_arn = "arn:aws:lambda:us-east-1:123456789012:function:auth:3" }
        ]
      },
      {
        path_pattern = "/static/*"
        invocations = [
          { event_type = "CloudFront Function - viewer response", function_arn = "arn:aws:cloudfront::123456789012:function/headers" }
        ]
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior[0].lambda_function_association) == 1
    error_message = "The /api/* behavior should carry its own Lambda@Edge association"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.static.ordered_cache_behavior[0].lambda_function_association).lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:auth:3"
    error_message = "The /api/* behavior should associate auth:3"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior[0].function_association) == 0
    error_message = "The /api/* behavior has no CloudFront Function"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior[1].function_association) == 1
    error_message = "The /static/* behavior should carry its own CloudFront Function association"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior[1].lambda_function_association) == 0
    error_message = "The /static/* behavior has no Lambda@Edge"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.ordered_cache_behavior[0].viewer_protocol_policy == "https-only"
    error_message = "Each behavior should carry its own viewer protocol policy"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.ordered_cache_behavior[0].compress == false
    error_message = "Each behavior should carry its own compression setting"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.ordered_cache_behavior[1].viewer_protocol_policy == "redirect-to-https"
    error_message = "A behavior that sets nothing should fall back to the defaults"
  }
}

# =============================================================================
# Test: Ordered behaviors cache the same fixed way as the default one
# =============================================================================
run "ordered_behaviors_caching_is_fixed" {
  command = plan

  variables {
    distribution_behaviors = [{ path_pattern = "/api/*" }]
  }

  assert {
    condition     = aws_cloudfront_distribution.static.ordered_cache_behavior[0].default_ttl == 3600
    error_message = "Ordered behaviors should keep the same fixed TTLs"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.static.ordered_cache_behavior[0].forwarded_values).query_string == false
    error_message = "Ordered behaviors should not forward query strings"
  }
}

# =============================================================================
# Test: Distribution-level options are configurable
# =============================================================================
run "distribution_options_are_configurable" {
  command = plan

  variables {
    distribution_price_class         = "PriceClass_All"
    distribution_default_root_object = "main.html"
    distribution_geo_restriction = {
      restriction_type = "whitelist"
      locations        = ["AR", "BR"]
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.static.price_class == "PriceClass_All"
    error_message = "Price class should be configurable"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_root_object == "main.html"
    error_message = "Default root object should be configurable"
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.static.restrictions).geo_restriction).restriction_type == "whitelist"
    error_message = "Geo restriction type should be configurable"
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.static.restrictions).geo_restriction).locations == toset(["AR", "BR"])
    error_message = "Geo restriction locations should be configurable"
  }
}

# =============================================================================
# Test: Custom error responses are opt-in (they break non-SPA apps)
# =============================================================================
run "no_custom_error_responses_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.static.custom_error_response) == 0
    error_message = "Should create no custom error responses unless configured"
  }
}

# =============================================================================
# Test: Custom error responses are created as configured (SPA case)
# =============================================================================
run "custom_error_responses_configured" {
  command = plan

  variables {
    distribution_custom_error_responses = [
      { error_code = 404, response_code = 200, response_page_path = "/index.html" },
      { error_code = 403, response_code = 200, response_page_path = "/index.html" }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.custom_error_response) == 2
    error_message = "Should create one custom error response per configured entry"
  }

  assert {
    condition = length([
      for r in aws_cloudfront_distribution.static.custom_error_response :
      r if r.error_code == 404 && r.response_code == 200 && r.response_page_path == "/index.html"
    ]) == 1
    error_message = "Should map 404 to /index.html with a 200 response code"
  }
}

# =============================================================================
# Test: Outputs from data source
# =============================================================================
run "outputs_from_data_source" {
  command = plan

  assert {
    condition     = output.distribution_bucket_name == "my-static-bucket"
    error_message = "distribution_bucket_name should be 'my-static-bucket'"
  }

  assert {
    condition     = output.distribution_bucket_arn == "arn:aws:s3:::my-static-bucket"
    error_message = "distribution_bucket_arn should be 'arn:aws:s3:::my-static-bucket'"
  }
}

# =============================================================================
# Test: Outputs from variables
# =============================================================================
run "outputs_from_variables" {
  command = plan

  assert {
    condition     = output.distribution_s3_prefix == "app/scope-1"
    error_message = "distribution_s3_prefix should be 'app/scope-1'"
  }
}

# =============================================================================
# Test: DNS-related outputs
# =============================================================================
run "dns_related_outputs" {
  command = plan

  assert {
    condition     = output.distribution_record_type == "A"
    error_message = "distribution_record_type should be 'A'"
  }
}

# =============================================================================
# Test: Website URL without network domain
# =============================================================================
run "website_url_without_network_domain" {
  command = plan

  # Without network domain, URL should use CloudFront domain (known after apply)
  # We can only check it starts with https://
  assert {
    condition     = startswith(output.distribution_website_url, "https://")
    error_message = "distribution_website_url should start with 'https://'"
  }
}

# =============================================================================
# Test: Website URL with network domain
# =============================================================================
run "website_url_with_network_domain" {
  command = plan

  variables {
    network_full_domain = "cdn.example.com"
  }

  assert {
    condition     = output.distribution_website_url == "https://cdn.example.com"
    error_message = "distribution_website_url should be 'https://cdn.example.com'"
  }
}

# =============================================================================
# Test: ACM certificate domain derivation
# =============================================================================
run "acm_certificate_domain_derived_from_network_domain" {
  command = plan

  variables {
    network_domain = "example.com"
  }

  assert {
    condition     = local.distribution_acm_certificate_domain == "*.example.com"
    error_message = "ACM certificate domain should be '*.example.com'"
  }
}

# =============================================================================
# Test: No ACM certificate lookup when network_domain is empty
# =============================================================================
run "no_acm_lookup_without_network_domain" {
  command = plan

  assert {
    condition     = local.distribution_acm_certificate_domain == ""
    error_message = "ACM certificate domain should be empty when network_domain is empty"
  }

  assert {
    condition     = local.distribution_has_acm_certificate == false
    error_message = "Should not have ACM certificate when network_domain is empty"
  }
}

# =============================================================================
# Test: Uses ACM certificate when network_domain is set
# =============================================================================
run "uses_acm_certificate_with_network_domain" {
  command = plan

  variables {
    network_domain      = "example.com"
    network_full_domain = "app.example.com"
  }

  assert {
    condition     = local.distribution_has_acm_certificate == true
    error_message = "Should have ACM certificate when network_domain is set"
  }
}

# =============================================================================
# Test: Uses default certificate without network_domain
# =============================================================================
run "uses_default_certificate_without_network_domain" {
  command = plan

  assert {
    condition     = local.distribution_has_acm_certificate == false
    error_message = "Should use default certificate when network_domain is empty"
  }
}

# =============================================================================
# Test: No WAF attached when security layer is "none"
# =============================================================================
run "no_waf_when_security_arn_null" {
  command = plan

  assert {
    condition     = local.distribution_web_acl_arn == null
    error_message = "web_acl_arn local should be null when the security layer does not expose an ARN"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.web_acl_id == null
    error_message = "Distribution web_acl_id should be null when no WAF is configured"
  }
}

# =============================================================================
# Test: WAF attached when security layer exposes an ARN
# =============================================================================
run "waf_attached_when_security_arn_set" {
  command = plan

  variables {
    security_web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test-acl/abcdef12-3456-7890-abcd-ef1234567890"
  }

  assert {
    condition     = local.distribution_web_acl_arn == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test-acl/abcdef12-3456-7890-abcd-ef1234567890"
    error_message = "web_acl_arn should mirror the value exposed by the security layer"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test-acl/abcdef12-3456-7890-abcd-ef1234567890"
    error_message = "Distribution web_acl_id should equal the WAFv2 ARN exposed by the security layer"
  }
}

# =============================================================================
# Test: Duplicated path patterns are rejected
# =============================================================================
run "rejects_duplicated_path_patterns" {
  command = plan

  variables {
    distribution_behaviors = [
      { path_pattern = "/api/*" },
      { path_pattern = "/api/*" }
    ]
  }

  expect_failures = [var.distribution_behaviors]
}

# =============================================================================
# Test: Lambda@Edge ARNs must include a published version
# =============================================================================
run "rejects_lambda_arn_without_version" {
  command = plan

  variables {
    distribution_default_behavior = {
      invocations = [{ event_type = "Lambda@Edge - viewer request", function_arn = "arn:aws:lambda:us-east-1:123456789012:function:my-fn" }]
    }
  }

  expect_failures = [var.distribution_default_behavior]
}

# =============================================================================
# Test: An unknown invocation is rejected
# =============================================================================
run "rejects_unknown_invocation" {
  command = plan

  variables {
    distribution_behaviors = [
      {
        path_pattern = "/api/*"
        invocations  = [{ event_type = "Lambda@Edge - whenever", function_arn = "arn:aws:lambda:us-east-1:123456789012:function:fn:1" }]
      }
    ]
  }

  expect_failures = [var.distribution_behaviors]
}

# =============================================================================
# Test: A CloudFront Function on an origin event is rejected
# =============================================================================
run "rejects_cloudfront_function_on_origin_event" {
  command = plan

  variables {
    distribution_default_behavior = {
      invocations = [{ event_type = "CloudFront Function - origin request", function_arn = "arn:aws:cloudfront::123456789012:function/fn" }]
    }
  }

  expect_failures = [var.distribution_default_behavior]
}

# =============================================================================
# Test: Invalid viewer protocol policy is rejected
# =============================================================================
run "rejects_invalid_viewer_protocol_policy" {
  command = plan

  variables {
    distribution_behaviors = [
      { path_pattern = "/api/*", viewer_protocol_policy = "always-http" }
    ]
  }

  expect_failures = [var.distribution_behaviors]
}

# =============================================================================
# Test: Invalid price class is rejected
# =============================================================================
run "rejects_invalid_price_class" {
  command = plan

  variables {
    distribution_price_class = "PriceClass_Cheap"
  }

  expect_failures = [var.distribution_price_class]
}
