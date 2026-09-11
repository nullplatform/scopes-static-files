#!/bin/bash
# =============================================================================
# CloudFront Assertion Functions
#
# Provides assertion functions for validating CloudFront distribution
# configuration in integration tests.
#
# Variables validated (from distribution/cloudfront/modules/variables.tf):
#   - distribution_bucket_name    -> Origin domain
#   - distribution_s3_prefix      -> Origin path
#   - distribution_app_name       -> Distribution comment
#   - distribution_resource_tags_json -> (skipped - Moto limitation)
#
# Usage:
#   source "cloudfront_assertions.bash"
#   assert_cloudfront_configured "comment" "domain" "bucket" "/prefix"
#
# Note: Some CloudFront fields are not fully supported by Moto and are skipped:
#   - DefaultRootObject, PriceClass, IsIPV6Enabled
#   - OriginAccessControlId, Compress, CachedMethods
#   - CustomErrorResponses, Tags
# =============================================================================

# =============================================================================
# CloudFront Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Distribution exists              | Non-empty ID                           |
# | Distribution enabled             | true                                   |
# | Distribution comment             | expected comment (exact match)         |
# | Custom domain alias              | expected_domain (exact match)          |
# | Origin domain                    | Contains expected_bucket               |
# | Origin path (S3 prefix)          | expected_origin_path (exact match)     |
# | Viewer protocol policy           | redirect-to-https                      |
# | Allowed methods                  | Contains GET, HEAD                     |
# +----------------------------------+----------------------------------------+
assert_cloudfront_configured() {
  local comment="$1"
  local expected_domain="$2"
  local expected_bucket="$3"
  local expected_origin_path="$4"

  # Get CloudFront distribution by comment
  local distribution_json
  distribution_json=$(aws_moto cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='$comment']" \
    --output json 2>/dev/null | jq '.[0]')

  # Distribution exists
  assert_not_empty "$distribution_json" "CloudFront distribution"

  local distribution_id
  distribution_id=$(echo "$distribution_json" | jq -r '.Id')
  assert_not_empty "$distribution_id" "CloudFront distribution ID"

  # Distribution enabled
  local distribution_enabled
  distribution_enabled=$(echo "$distribution_json" | jq -r '.Enabled')
  assert_true "$distribution_enabled" "CloudFront distribution enabled"

  # Distribution comment (validates distribution_app_name)
  local actual_comment
  actual_comment=$(echo "$distribution_json" | jq -r '.Comment')
  assert_equal "$actual_comment" "$comment"

  # Custom domain alias (exact match - only one alias expected)
  local alias
  alias=$(echo "$distribution_json" | jq -r '.Aliases.Items[0] // empty')
  if [[ -n "$alias" && "$alias" != "null" ]]; then
    assert_equal "$alias" "$expected_domain"
  fi

  # Origin domain (validates distribution_bucket_name)
  local origin_domain
  origin_domain=$(echo "$distribution_json" | jq -r '.Origins.Items[0].DomainName // empty')
  assert_not_empty "$origin_domain" "Origin domain"
  assert_contains "$origin_domain" "$expected_bucket"

  # Origin path (validates distribution_s3_prefix)
  local origin_path
  origin_path=$(echo "$distribution_json" | jq -r '.Origins.Items[0].OriginPath // empty')
  assert_equal "$origin_path" "$expected_origin_path"

  # Default cache behavior - viewer protocol policy
  local viewer_protocol_policy
  viewer_protocol_policy=$(echo "$distribution_json" | jq -r '.DefaultCacheBehavior.ViewerProtocolPolicy // empty')
  if [[ -n "$viewer_protocol_policy" && "$viewer_protocol_policy" != "null" ]]; then
    assert_equal "$viewer_protocol_policy" "redirect-to-https"
  fi

  # Default cache behavior - allowed methods (check GET and HEAD are present)
  local allowed_methods
  allowed_methods=$(echo "$distribution_json" | jq -r '.DefaultCacheBehavior.AllowedMethods.Items // [] | join(",")')
  if [[ -n "$allowed_methods" ]]; then
    assert_contains "$allowed_methods" "GET"
    assert_contains "$allowed_methods" "HEAD"
  fi

  # Default cache behavior - CachingOptimized (managed policy ids are global constants)
  local default_cache_policy_id
  default_cache_policy_id=$(echo "$distribution_json" | jq -r '.DefaultCacheBehavior.CachePolicyId // empty')
  assert_equal "$default_cache_policy_id" "658327ea-f89d-4fab-a63d-7e88639e58f6"

  # Ordered cache behaviors - one per configured behavior, in order
  local behavior_count
  behavior_count=$(echo "$distribution_json" | jq -r '.CacheBehaviors.Quantity // 0')
  assert_equal "$behavior_count" "2"

  local path_patterns
  path_patterns=$(echo "$distribution_json" | jq -r '[.CacheBehaviors.Items[].PathPattern] | join(",")')
  assert_equal "$path_patterns" "/api/*,/static/*"

  # Each behavior carries its own cache policy: /api/* is CachingDisabled, /static/* is
  # CachingOptimizedForUncompressedObjects — neither shares the default behavior's policy
  local api_cache_policy_id static_cache_policy_id
  api_cache_policy_id=$(echo "$distribution_json" | jq -r '.CacheBehaviors.Items[0].CachePolicyId // empty')
  static_cache_policy_id=$(echo "$distribution_json" | jq -r '.CacheBehaviors.Items[1].CachePolicyId // empty')
  assert_equal "$api_cache_policy_id" "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  assert_equal "$static_cache_policy_id" "b2884449-e4de-46a7-ac36-70bc7f1ddd6d"

  # Custom error responses (SPA routing)
  local error_response_count
  error_response_count=$(echo "$distribution_json" | jq -r '.CustomErrorResponses.Quantity // 0')
  assert_equal "$error_response_count" "2"
}

# =============================================================================
# CloudFront Not Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Distribution exists              | null/empty (deleted)                   |
# +----------------------------------+----------------------------------------+
assert_cloudfront_not_configured() {
  local comment="$1"

  local distribution_json
  distribution_json=$(aws_moto cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='$comment']" \
    --output json 2>/dev/null | jq '.[0]')

  # jq returns "null" when array is empty, treat as deleted
  if [[ -z "$distribution_json" || "$distribution_json" == "null" ]]; then
    return 0
  fi

  echo "Expected CloudFront distribution to be deleted"
  echo "Actual: '$distribution_json'"
  return 1
}
