#!/usr/bin/env bats
# =============================================================================
# Unit tests for build_context script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/scripts/build_context_test.bats
# =============================================================================

scope_id=7

# Setup - runs before each test
setup() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
	PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

	source "$PROJECT_ROOT/testing/assertions.sh"

	CONTEXT=$(cat "$PROJECT_DIR/tests/resources/context.json")
	SERVICE_PATH="$PROJECT_DIR"
	TEST_OUTPUT_DIR=$(mktemp -d)
	NP_MOCKS_DIR="$PROJECT_DIR/tests/resources/np_mocks"
	SCOPE_CFG_MOCKS="$NP_MOCKS_DIR/scope_configuration"

	export PATH="$NP_MOCKS_DIR:$PATH"
	export NP_MOCK_SPECIFICATION_LIST="$SCOPE_CFG_MOCKS/specification_list.json"
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list.json"
	export CONTEXT SERVICE_PATH TEST_OUTPUT_DIR SCOPE_CFG_MOCKS
}

# Teardown - runs after each test
teardown() {
	if [ -d "$TEST_OUTPUT_DIR" ]; then
		rm -rf "$TEST_OUTPUT_DIR"
	fi
}

# =============================================================================
# Helper functions
# =============================================================================
run_build_context() {
	source "$PROJECT_DIR/scripts/build_context"
}

# =============================================================================
# Test: Layer resolution from scope-configurations provider
# =============================================================================
@test "Should resolve TOFU_PROVIDER from scope-configurations provider" {
	run_build_context

	assert_equal "$TOFU_PROVIDER" "aws"
}

@test "Should resolve NETWORK_LAYER from scope-configurations provider" {
	run_build_context

	assert_equal "$NETWORK_LAYER" "route53"
}

@test "Should resolve DISTRIBUTION_LAYER from scope-configurations provider" {
	run_build_context

	assert_equal "$DISTRIBUTION_LAYER" "cloudfront"
}

@test "Should fall back to env vars for TOFU_PROVIDER when not in CONTEXT" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].cloud_provider)')
	export TOFU_PROVIDER="azure"
	export NETWORK_LAYER="azure_dns"
	export DISTRIBUTION_LAYER="blob-cdn"

	run_build_context

	assert_equal "$TOFU_PROVIDER" "azure"
}

@test "Should fall back to env vars for NETWORK_LAYER when not in CONTEXT" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].network.aws_network)')
	export NETWORK_LAYER="azure_dns"

	run_build_context

	assert_equal "$NETWORK_LAYER" "azure_dns"
}

@test "Should fall back to env vars for DISTRIBUTION_LAYER when not in CONTEXT" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].distribution.aws_distribution)')
	export DISTRIBUTION_LAYER="blob-cdn"

	run_build_context

	assert_equal "$DISTRIBUTION_LAYER" "blob-cdn"
}

@test "Should fail when cloud_provider is not configured anywhere" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].cloud_provider)')
	unset TOFU_PROVIDER

	run source "$PROJECT_DIR/scripts/build_context"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ cloud_provider is not configured"
	assert_contains "$output" "scope-configurations provider"
}

@test "Should fail when network layer is not configured anywhere" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].network.aws_network)')
	unset NETWORK_LAYER

	run source "$PROJECT_DIR/scripts/build_context"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ network layer is not configured"
}

@test "Should fail when distribution layer is not configured anywhere" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].distribution.aws_distribution)')
	unset DISTRIBUTION_LAYER

	run source "$PROJECT_DIR/scripts/build_context"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ distribution layer is not configured"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should generate TOFU_VARIABLES with expected structure" {
	run_build_context

	local expected='{}'

	assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES
# =============================================================================
@test "Should generate correct tf_state_key format in TOFU_INIT_VARIABLES" {
	run_build_context

	assert_contains "$TOFU_INIT_VARIABLES" "key=nullplatform/scopes/static-files/tools/automation/development-tools-$scope_id"
}

# =============================================================================
# Test: TOFU_MODULE_DIR
# =============================================================================
@test "Should create TOFU_MODULE_DIR path with scope_id" {
	run_build_context

	assert_contains "$TOFU_MODULE_DIR" "$SERVICE_PATH/output/$scope_id"
}

@test "Should create TOFU_MODULE_DIR as a directory" {
	run_build_context

	assert_directory_exists "$TOFU_MODULE_DIR"
}

# =============================================================================
# Test: MODULES_TO_USE initialization
# =============================================================================
@test "Should initialize MODULES_TO_USE as empty by default" {
	unset CUSTOM_TOFU_MODULES
	run_build_context

	assert_empty "$MODULES_TO_USE" "MODULES_TO_USE"
}

@test "Should inherit MODULES_TO_USE from CUSTOM_TOFU_MODULES" {
	export CUSTOM_TOFU_MODULES="custom/module1,custom/module2"
	run_build_context

	assert_equal "$MODULES_TO_USE" "custom/module1,custom/module2"
}

# =============================================================================
# Test: exports are set
# =============================================================================
@test "Should export TOFU_VARIABLES" {
	run_build_context

	assert_not_empty "$TOFU_VARIABLES" "TOFU_VARIABLES"
}

@test "Should export TOFU_INIT_VARIABLES" {
	run_build_context

	assert_not_empty "$TOFU_INIT_VARIABLES" "TOFU_INIT_VARIABLES"
}

@test "Should export TOFU_MODULE_DIR" {
	run_build_context

	assert_not_empty "$TOFU_MODULE_DIR" "TOFU_MODULE_DIR"
}

@test "Should export TOFU_PROVIDER" {
	run_build_context

	assert_not_empty "$TOFU_PROVIDER" "TOFU_PROVIDER"
}

@test "Should export NETWORK_LAYER" {
	run_build_context

	assert_not_empty "$NETWORK_LAYER" "NETWORK_LAYER"
}

@test "Should export DISTRIBUTION_LAYER" {
	run_build_context

	assert_not_empty "$DISTRIBUTION_LAYER" "DISTRIBUTION_LAYER"
}

# =============================================================================
# Test: RESOURCE_TAGS_JSON - verifies the entire JSON structure
# =============================================================================
@test "Should generate RESOURCE_TAGS_JSON with expected structure" {
	run_build_context

	local expected='{
	"account": "playground",
	"account_id": 2,
	"application": "automation",
	"application_id": 4,
	"deployment_id": 8,
	"namespace": "tools",
	"namespace_id": 3,
	"nullplatform": "true",
	"scope": "development-tools",
	"scope_id": 7
	}'

	assert_json_equal "$RESOURCE_TAGS_JSON" "$expected" "RESOURCE_TAGS_JSON"
}

# =============================================================================
# Test: The scope reads its own configuration
#
# Every scope type in an account shares the scope-configurations category and
# the context carries a single one — whichever provider resolves closest in the
# NRN hierarchy, which is another scope type's when both sit at the same level.
# =============================================================================
@test "Should replace a scope-configuration belonging to another scope type" {
	export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"] = {"deployment": {"placeholder_image_uri": "lambda-placeholder"}}')

	run_build_context

	assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"].marker')" "static-configuration"
	assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"].deployment // "gone"')" "gone"
}

@test "Should pick the configuration closest to the scope when there are several" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_nested.json"

	run_build_context

	assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"].marker')" "application-level"
}

@test "Should keep the context untouched when no configuration is found" {
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_empty.json"
	export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].marker = "from-context"')

	run_build_context

	assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"].marker')" "from-context"
}

# =============================================================================
# Test: The scope reads the configuration matching its own dimensions
#
# Two static-files configurations can sit at the same NRN level, one per
# dimension value (e.g. environment=dev and environment=test). The NRN-depth
# tie-break alone can't tell them apart, so the query must also be scoped by
# the scope's own dimensions.
# =============================================================================
@test "Should pick the configuration matching the scope's own dimensions when several tie on NRN depth" {
	export CONTEXT=$(echo "$CONTEXT" | jq '.scope.dimensions = {"environment": "test"}')
	export NP_MOCK_PROVIDER_LIST="$SCOPE_CFG_MOCKS/provider_list_dimension_conflict_unfiltered.json"
	export NP_MOCK_PROVIDER_LIST_WITH_DIMENSIONS="$SCOPE_CFG_MOCKS/provider_list_dimension_conflict_filtered.json"

	run_build_context

	assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"].marker')" "test-configuration"
	assert_equal "$(echo "$CONTEXT" | jq -r '.providers["scope-configurations"].provider.aws_state_bucket')" "test-account-tofu-state"
}
