#!/usr/bin/env bats
# =============================================================================
# Unit tests for distribution/blob-cdn/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/distribution/blob-cdn/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/distribution/blob-cdn/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Load context with Azure-specific asset URL
  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7", "nrn": "organization=1:account=2:namespace=3:application=4:scope=7"},
    "asset": {"url": "https://mystaticstorage.blob.core.windows.net/assets/tools/automation/v1.0.0"}
  }'

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
run_blob_cdn_setup() {
  source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Storage account extraction from asset URL
# =============================================================================
@test "Should extract storage account from asset URL" {
  run_blob_cdn_setup

  local storage_account=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_storage_account')
  assert_equal "$storage_account" "mystaticstorage"
}

# =============================================================================
# Test: Container extraction from asset URL
# =============================================================================
@test "Should extract container name from asset URL" {
  run_blob_cdn_setup

  local container=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')
  assert_equal "$container" "assets"
}

@test "Should default container to \$web when URL has no container path" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/"')

  run_blob_cdn_setup

  local container=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')
  assert_equal "$container" '$web'
}

# =============================================================================
# Test: Blob prefix extraction from asset URL
# =============================================================================
@test "Should extract blob_prefix from asset.url with https format" {
  run_blob_cdn_setup

  local blob_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')
  assert_equal "$blob_prefix" "/tools/automation/v1.0.0"
}

@test "Should use root prefix when asset URL has no path after container" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/assets"')

  run_blob_cdn_setup

  local blob_prefix=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')
  assert_equal "$blob_prefix" "/"
}

# =============================================================================
# Test: Invalid asset URL
# =============================================================================
@test "Should fail when asset URL is not Azure Blob Storage format" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "s3://bucket/path"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not extract storage account from asset URL"
  assert_contains "$output" "🔧 How to fix:"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add distribution variables to TOFU_VARIABLES" {
  run_blob_cdn_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_storage_account": "mystaticstorage",
  "distribution_container_name": "assets",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_blob_prefix": "/tools/automation/v1.0.0",
  "distribution_resource_tags_json": {}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should add distribution_resource_tags_json to TOFU_VARIABLES" {
  export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

  run_blob_cdn_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_storage_account": "mystaticstorage",
  "distribution_container_name": "assets",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_blob_prefix": "/tools/automation/v1.0.0",
  "distribution_resource_tags_json": {"Environment": "production", "Team": "platform"}
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  run_blob_cdn_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/distribution/blob-cdn/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_blob_cdn_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/distribution/blob-cdn/modules"
}
