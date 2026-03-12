#!/usr/bin/env bats
# =============================================================================
# Unit tests for distribution/static-web-apps/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/distribution/static-web-apps/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
	PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
	SCRIPT_PATH="$PROJECT_DIR/distribution/static-web-apps/setup"
	RESOURCES_DIR="$PROJECT_DIR/tests/resources"

	# Load shared test utilities
	source "$PROJECT_ROOT/testing/assertions.sh"

	# Add mock az to PATH (must be first)
	export PATH="$RESOURCES_DIR/az_mocks:$PATH"

	# Load context with Azure-specific asset URL
	export CONTEXT='{
		"application": {"slug": "automation"},
		"scope": {"slug": "development-tools", "id": "7", "nrn": "organization=1:account=2:namespace=3:application=4:scope=7"},
		"asset": {"url": "https://mystaticstorage.blob.core.windows.net/$web/tools/automation/v1.0.0"}
	}'

	# Initialize TOFU_VARIABLES with required fields
	export TOFU_VARIABLES='{
		"application_slug": "automation",
		"scope_slug": "development-tools",
		"scope_id": "7"
	}'

	export MODULES_TO_USE=""
	export RESOURCE_TAGS_JSON="{}"

	# Default mock scenario
	export AZ_MOCK_SCENARIO="download-batch-success"
}

# =============================================================================
# Helper functions
# =============================================================================
set_az_mock_scenario() {
	export AZ_MOCK_SCENARIO="$1"
}

run_swa_setup() {
	source "$SCRIPT_PATH"
}

# =============================================================================
# Test: distribution_app_name
# =============================================================================
@test "Should build distribution_app_name from context" {
	run_swa_setup

	local app_name
	app_name=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_app_name')
	assert_equal "$app_name" "automation-development-tools-7"
}

# =============================================================================
# Test: Missing asset.url
# =============================================================================
@test "Should fail when asset.url is missing" {
	export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = null')

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "No asset URL found in context"
}

# =============================================================================
# Test: Unsupported asset.url format
# =============================================================================
@test "Should fail when asset.url format is unsupported" {
	export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "s3://bucket/path"')

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "Asset URL is not in the expected Azure Blob Storage format"
}

# =============================================================================
# Test: Download failure
# =============================================================================
@test "Should fail when download fails" {
	set_az_mock_scenario "download-batch-failure"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "Failed to download artifact from Azure Blob Storage"
}

# =============================================================================
# Test: Default SKU tier
# =============================================================================
@test "Should default SKU tier to Free" {
	run_swa_setup

	local sku_tier
	sku_tier=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_sku_tier')
	assert_equal "$sku_tier" "Free"
}

# =============================================================================
# Test: Custom SKU tier from environment
# =============================================================================
@test "Should use SWA_SKU_TIER from environment" {
	export SWA_SKU_TIER="Standard"

	run_swa_setup

	local sku_tier
	sku_tier=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_sku_tier')
	assert_equal "$sku_tier" "Standard"
}

# =============================================================================
# Test: Default location
# =============================================================================
@test "Should default location to eastus2" {
	run_swa_setup

	local location
	location=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_location')
	assert_equal "$location" "eastus2"
}

# =============================================================================
# Test: Custom location from environment
# =============================================================================
@test "Should use SWA_LOCATION from environment" {
	export SWA_LOCATION="westeurope"

	run_swa_setup

	local location
	location=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_location')
	assert_equal "$location" "westeurope"
}

# =============================================================================
# Test: All distribution variables in TOFU_VARIABLES
# =============================================================================
@test "Should add distribution variables to TOFU_VARIABLES" {
	run_swa_setup

	assert_not_empty "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_app_name')" "distribution_app_name"
	assert_not_empty "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_sku_tier')" "distribution_sku_tier"
	assert_not_empty "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_location')" "distribution_location"
	assert_not_empty "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_artifact_url')" "distribution_artifact_url"
	assert_not_empty "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_artifact_dir')" "distribution_artifact_dir"

	local tags_type
	tags_type=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_resource_tags_json | type')
	assert_equal "$tags_type" "object"
}

# =============================================================================
# Test: Resource tags in TOFU_VARIABLES
# =============================================================================
@test "Should add resource tags to TOFU_VARIABLES" {
	export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

	run_swa_setup

	local tags
	tags=$(echo "$TOFU_VARIABLES" | jq -r '.distribution_resource_tags_json')
	assert_contains "$tags" "production"
	assert_contains "$tags" "platform"
}

# =============================================================================
# Test: MODULES_TO_USE when empty
# =============================================================================
@test "Should register module in MODULES_TO_USE when empty" {
	run_swa_setup

	assert_contains "$MODULES_TO_USE" "static-web-apps/modules"
}

# =============================================================================
# Test: MODULES_TO_USE when not empty
# =============================================================================
@test "Should append module in MODULES_TO_USE when not empty" {
	export MODULES_TO_USE="existing/module"

	run_swa_setup

	assert_contains "$MODULES_TO_USE" "existing/module,"
	assert_contains "$MODULES_TO_USE" "static-web-apps/modules"
}
