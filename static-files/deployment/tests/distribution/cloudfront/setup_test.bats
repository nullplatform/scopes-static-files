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
  assert_contains "$output" "❌ Could not extract S3 bucket name from asset URL"
  assert_contains "$output" "🔧 How to fix:"
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
