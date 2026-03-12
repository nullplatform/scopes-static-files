#!/usr/bin/env bats
# =============================================================================
# Unit tests for provider/azure/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/provider/azure/setup_test.bats
# =============================================================================

setup() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
	PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
	SCRIPT_PATH="$PROJECT_DIR/provider/azure/setup"

	source "$PROJECT_ROOT/testing/assertions.sh"

	# Env var fallbacks (no CONTEXT in unit tests)
	export AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
	export AZURE_RESOURCE_GROUP="my-resource-group"
	export TOFU_PROVIDER_STORAGE_ACCOUNT="mytfstatestorage"
	export TOFU_PROVIDER_CONTAINER="tfstate"

	# Base tofu variables
	export TOFU_VARIABLES='{
	"application_slug": "automation",
	"scope_slug": "development-tools",
	"scope_id": "7"
	}'

	export TOFU_INIT_VARIABLES=""
	export MODULES_TO_USE=""
}

# =============================================================================
# Helper functions
# =============================================================================
run_azure_setup() {
	source "$SCRIPT_PATH"
}

# =============================================================================
# Test: Required environment variables (via env var fallback)
# =============================================================================
@test "Should fail when azure_subscription_id is not available" {
	unset AZURE_SUBSCRIPTION_ID

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ azure_subscription_id is missing"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "provider.azure_subscription_id"
}

@test "Should fail when azure_resource_group is not available" {
	unset AZURE_RESOURCE_GROUP

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ azure_resource_group is missing"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "provider.azure_resource_group"
}

@test "Should fail when azure_state_storage_account is not available" {
	unset TOFU_PROVIDER_STORAGE_ACCOUNT

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ azure_state_storage_account is missing"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "provider.azure_state_storage_account"
}

@test "Should fail when azure_state_container is not available" {
	unset TOFU_PROVIDER_CONTAINER

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ azure_state_container is missing"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "provider.azure_state_container"
}

@test "Should report all the variables that are not set" {
	unset AZURE_SUBSCRIPTION_ID
	unset AZURE_RESOURCE_GROUP
	unset TOFU_PROVIDER_STORAGE_ACCOUNT
	unset TOFU_PROVIDER_CONTAINER

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ azure_subscription_id is missing"
	assert_contains "$output" "❌ azure_resource_group is missing"
	assert_contains "$output" "❌ azure_state_storage_account is missing"
	assert_contains "$output" "❌ azure_state_container is missing"
	assert_contains "$output" "🔧 How to fix:"
	assert_contains "$output" "provider.azure_subscription_id"
	assert_contains "$output" "provider.azure_resource_group"
	assert_contains "$output" "provider.azure_state_storage_account"
	assert_contains "$output" "provider.azure_state_container"
}

# =============================================================================
# Test: Resolve from scope-configurations provider (CONTEXT)
# =============================================================================
@test "Should resolve values from scope-configurations provider in CONTEXT" {
	unset AZURE_SUBSCRIPTION_ID
	unset AZURE_RESOURCE_GROUP
	unset TOFU_PROVIDER_STORAGE_ACCOUNT
	unset TOFU_PROVIDER_CONTAINER

	export CONTEXT='{
	"providers": {
		"scope-configurations": {
		"provider": {
			"azure_subscription_id": "11111111-1111-1111-1111-111111111111",
			"azure_resource_group": "provider-rg",
			"azure_state_storage_account": "providerstate",
			"azure_state_container": "providercontainer"
		}
		}
	}
	}'

	run_azure_setup

	local actual_sub=$(echo "$TOFU_VARIABLES" | jq -r '.azure_provider.subscription_id')
	local actual_rg=$(echo "$TOFU_VARIABLES" | jq -r '.azure_provider.resource_group')
	local actual_sa=$(echo "$TOFU_VARIABLES" | jq -r '.azure_provider.storage_account')
	local actual_ct=$(echo "$TOFU_VARIABLES" | jq -r '.azure_provider.container')

	assert_equal "$actual_sub" "11111111-1111-1111-1111-111111111111"
	assert_equal "$actual_rg" "provider-rg"
	assert_equal "$actual_sa" "providerstate"
	assert_equal "$actual_ct" "providercontainer"
}

@test "Should prefer provider values over env vars" {
	export AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
	export AZURE_RESOURCE_GROUP="env-rg"

	export CONTEXT='{
	"providers": {
		"scope-configurations": {
		"provider": {
			"azure_subscription_id": "11111111-1111-1111-1111-111111111111",
			"azure_resource_group": "provider-rg",
			"azure_state_storage_account": "providerstate",
			"azure_state_container": "providercontainer"
		}
		}
	}
	}'

	run_azure_setup

	local actual_sub=$(echo "$TOFU_VARIABLES" | jq -r '.azure_provider.subscription_id')
	local actual_rg=$(echo "$TOFU_VARIABLES" | jq -r '.azure_provider.resource_group')

	assert_equal "$actual_sub" "11111111-1111-1111-1111-111111111111"
	assert_equal "$actual_rg" "provider-rg"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add azure_provider field to TOFU_VARIABLES" {
	run_azure_setup

	local expected='{
	"application_slug": "automation",
	"scope_slug": "development-tools",
	"scope_id": "7",
	"azure_provider": {
	"subscription_id": "00000000-0000-0000-0000-000000000000",
	"resource_group": "my-resource-group",
	"storage_account": "mytfstatestorage",
	"container": "tfstate"
	},
	"provider_resource_tags_json": {}
	}'

	assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should add provider_resource_tags_json to TOFU_VARIABLES" {
	export RESOURCE_TAGS_JSON='{"Environment": "production", "Team": "platform"}'

	run_azure_setup

	local expected='{
	"application_slug": "automation",
	"scope_slug": "development-tools",
	"scope_id": "7",
	"azure_provider": {
	"subscription_id": "00000000-0000-0000-0000-000000000000",
	"resource_group": "my-resource-group",
	"storage_account": "mytfstatestorage",
	"container": "tfstate"
	},
	"provider_resource_tags_json": {"Environment": "production", "Team": "platform"}
	}'

	assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

# =============================================================================
# Test: TOFU_INIT_VARIABLES - backend configuration
# =============================================================================
@test "Should add storage_account_name configuration to TOFU_INIT_VARIABLES" {
	run_azure_setup

	assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=storage_account_name=mytfstatestorage"
}

@test "Should add container_name configuration to TOFU_INIT_VARIABLES" {
	run_azure_setup

	assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=container_name=tfstate"
}

@test "Should add resource_group_name configuration to TOFU_INIT_VARIABLES" {
	run_azure_setup

	assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=resource_group_name=my-resource-group"
}

@test "Should append to TOFU_INIT_VARIABLES when it previous settings are present" {
	export TOFU_INIT_VARIABLES="-var=existing=value"

	run_azure_setup

	assert_equal "$TOFU_INIT_VARIABLES" "-var=existing=value -backend-config=storage_account_name=mytfstatestorage -backend-config=container_name=tfstate -backend-config=resource_group_name=my-resource-group"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
	run_azure_setup

	assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/provider/azure/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
	export MODULES_TO_USE="existing/module"

	run_azure_setup

	assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/provider/azure/modules"
}
