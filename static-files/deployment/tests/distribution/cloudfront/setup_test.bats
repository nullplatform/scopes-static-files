#!/usr/bin/env bats
# =============================================================================
# Unit tests for distribution/cloudfront/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/distribution/cloudfront/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/distribution/cloudfront/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Load context
  export CONTEXT=$(cat "$RESOURCES_DIR/context.json")

  # Initialize TOFU_VARIABLES with required fields
  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export MODULES_TO_USE=""

  # Mock AWS CLI — controlled via MOCK_AWS_ACCOUNT_ID and MOCK_AWS_BUCKET_POLICY
  MOCK_AWS_ACCOUNT_ID="123456789012"
  MOCK_AWS_BUCKET_POLICY='{"Version":"2012-10-17","Statement":[{"Sid":"AllowCloudFrontServicePrincipalReadOnly","Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::my-asset-bucket/*","Condition":{"StringEquals":{"AWS:SourceAccount":"123456789012"}}}]}'
  export MOCK_AWS_ACCOUNT_ID MOCK_AWS_BUCKET_POLICY

  aws() {
    if [[ "$*" == *"sts get-caller-identity"* ]]; then
      [ -n "${MOCK_AWS_ACCOUNT_ID:-}" ] && echo "$MOCK_AWS_ACCOUNT_ID"
    elif [[ "$*" == *"s3api get-bucket-policy"* ]]; then
      [ -n "${MOCK_AWS_BUCKET_POLICY:-}" ] && echo "$MOCK_AWS_BUCKET_POLICY"
    fi
  }
  export -f aws
}

# =============================================================================
# Helper functions
# =============================================================================
run_cloudfront_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Bucket name extraction from asset_url
# =============================================================================
@test "Should extract bucket name from s3:// asset URL" {
  run_cloudfront_setup

  local bucket=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_bucket_name')
  assert_equal "$bucket" "my-asset-bucket"
}

@test "Should extract bucket name from s3:// URL with .s3.amazonaws.com suffix" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "s3://my-asset-bucket.s3.amazonaws.com/tools/automation/v1.0.0"')

  run_cloudfront_setup

  local bucket=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_bucket_name')
  assert_equal "$bucket" "my-asset-bucket"
}

@test "Should extract bucket name from https:// asset URL" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://my-cdn-bucket.s3.amazonaws.com/tools/automation/v1.0.0"')

  run_cloudfront_setup

  local bucket=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_bucket_name')
  assert_equal "$bucket" "my-cdn-bucket"
}

# =============================================================================
# Test: S3 prefix extraction from asset URL
# =============================================================================
@test "Should extract s3_prefix from asset.url with s3 format" {
  run_cloudfront_setup

  local s3_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_s3_prefix')
  assert_equal "$s3_prefix" "/tools/automation/v1.0.0"
}

@test "Should extract s3_prefix from asset.url with https format" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://my-cdn-bucket.s3.amazonaws.com/tools/automation/v1.0.0"')

  run_cloudfront_setup

  local s3_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_s3_prefix')
  assert_equal "$s3_prefix" "/tools/automation/v1.0.0"
}

# =============================================================================
# Test: Invalid asset URL
# =============================================================================
@test "Should fail when bucket name cannot be extracted" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = ""')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not extract S3 bucket name from asset URL: "
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• The asset URL format is not recognized"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Ensure the asset URL uses 's3://bucket/path' or 'https://bucket.s3.amazonaws.com/path' format"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add distribution variables to TOFU_VARIABLES" {
  run_cloudfront_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_bucket_name": "my-asset-bucket",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_resource_tags_json": {},
  "distribution_s3_prefix": "/tools/automation/v1.0.0"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should add distribution_resource_tags_json to TOFU_VARIABLES" {
  export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

  run_cloudfront_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_bucket_name": "my-asset-bucket",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_resource_tags_json": {"Environment": "production", "Team": "platform"},
  "distribution_s3_prefix": "/tools/automation/v1.0.0"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  run_cloudfront_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/distribution/cloudfront/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_cloudfront_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/distribution/cloudfront/modules"
}

# =============================================================================
# Test: Bucket policy validation
# =============================================================================
@test "Should pass when bucket policy allows CloudFront access for the current account" {
  run source "$SCRIPT_PATH"

  assert_contains "$output" "✅ bucket_policy=allows CloudFront access for account 123456789012"
}

@test "Should fail when no bucket policy exists on the S3 bucket" {
  export MOCK_AWS_BUCKET_POLICY=""

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ No bucket policy found on S3 bucket: my-asset-bucket"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• The bucket policy has not been created yet"
  assert_contains "$output" "• The bucket policy was removed when a CloudFront distribution was deleted"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Apply the bucket module that manages the S3 bucket policy for CloudFront OAC access"
  assert_contains "$output" "• The policy must allow cloudfront.amazonaws.com with s3:GetObject and AWS:SourceAccount condition"
}

@test "Should fail when bucket policy does not allow cloudfront.amazonaws.com" {
  export MOCK_AWS_BUCKET_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::my-asset-bucket/*"}]}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Bucket policy on 'my-asset-bucket' does not allow CloudFront access for account 123456789012"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• The policy is missing a statement for cloudfront.amazonaws.com"
  assert_contains "$output" "• The AWS:SourceAccount condition does not match account 123456789012"
  assert_contains "$output" "• The policy does not grant s3:GetObject"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "• Ensure the bucket module applies a policy with:"
  assert_contains "$output" "- Principal: { Service: cloudfront.amazonaws.com }"
  assert_contains "$output" "- Action: s3:GetObject"
  assert_contains "$output" "- Condition: { StringEquals: { AWS:SourceAccount: 123456789012 } }"
}

@test "Should fail when bucket policy has wrong AWS account in condition" {
  export MOCK_AWS_BUCKET_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::my-asset-bucket/*","Condition":{"StringEquals":{"AWS:SourceAccount":"999999999999"}}}]}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Bucket policy on 'my-asset-bucket' does not allow CloudFront access for account 123456789012"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• The AWS:SourceAccount condition does not match account 123456789012"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Condition: { StringEquals: { AWS:SourceAccount: 123456789012 } }"
}

@test "Should fail when bucket policy denies s3:GetObject" {
  export MOCK_AWS_BUCKET_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::my-asset-bucket/*","Condition":{"StringEquals":{"AWS:SourceAccount":"123456789012"}}}]}'

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Bucket policy on 'my-asset-bucket' does not allow CloudFront access for account 123456789012"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "• The policy does not grant s3:GetObject"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "- Action: s3:GetObject"
}

@test "Should accept bucket policy with s3:GetObject in an array of actions" {
  export MOCK_AWS_BUCKET_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":["s3:GetObject","s3:ListBucket"],"Resource":"arn:aws:s3:::my-asset-bucket/*","Condition":{"StringEquals":{"AWS:SourceAccount":"123456789012"}}}]}'

  run_cloudfront_setup
}
