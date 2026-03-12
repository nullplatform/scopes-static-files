#!/usr/bin/env bats
# =============================================================================
# Unit tests for layer_executor script
#
# Requirements:
#   - bats-core: brew install bats-core
#
# Run tests:
#   bats tests/scripts/layer_executor_test.bats
# =============================================================================

setup() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
	PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
	SCRIPT_PATH="$PROJECT_DIR/scripts/layer_executor"

	source "$PROJECT_ROOT/testing/assertions.sh"

	# Create temporary directory structure for mock layers
	TEST_LAYERS_DIR=$(mktemp -d)
	export SERVICE_PATH="$TEST_LAYERS_DIR"

	# Create deployment directory structure
	mkdir -p "$TEST_LAYERS_DIR/deployment/provider/aws"
	mkdir -p "$TEST_LAYERS_DIR/deployment/network/route53"
	mkdir -p "$TEST_LAYERS_DIR/deployment/distribution/cloudfront"
	mkdir -p "$TEST_LAYERS_DIR/deployment/scripts"

	# Copy get_config_value so setup scripts can source it
	cp "$PROJECT_DIR/scripts/get_config_value" "$TEST_LAYERS_DIR/deployment/scripts/get_config_value"
}

teardown() {
	if [ -d "$TEST_LAYERS_DIR" ]; then
		rm -rf "$TEST_LAYERS_DIR"
	fi
}

# =============================================================================
# Helper functions
# =============================================================================
create_setup_script() {
	local layer_type="$1"
	local layer_name="$2"
	local content="${3:-echo 'Setup executed for $layer_type/$layer_name'}"

	mkdir -p "$TEST_LAYERS_DIR/deployment/${layer_type}/${layer_name}"
	cat > "$TEST_LAYERS_DIR/deployment/${layer_type}/${layer_name}/setup" <<EOF
#!/bin/bash
$content
EOF
	chmod +x "$TEST_LAYERS_DIR/deployment/${layer_type}/${layer_name}/setup"
}

# =============================================================================
# Test: Missing configuration variables
# =============================================================================
@test "Should fail when LAYER_TYPE is not set" {
	unset LAYER_TYPE
	export LAYER_VAR="TOFU_PROVIDER"
	export TOFU_PROVIDER="aws"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ LAYER_TYPE is not set"
	assert_contains "$output" "🔧 How to fix"
}

@test "Should fail when LAYER_VAR is not set" {
	export LAYER_TYPE="provider"
	unset LAYER_VAR

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ LAYER_VAR is not set"
	assert_contains "$output" "🔧 How to fix"
}

# =============================================================================
# Test: Missing layer variable value
# =============================================================================
@test "Should fail when the layer variable has no value" {
	export LAYER_TYPE="provider"
	export LAYER_VAR="TOFU_PROVIDER"
	unset TOFU_PROVIDER

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ TOFU_PROVIDER is not set"
	assert_contains "$output" "build_context did not resolve the provider layer"
	assert_contains "$output" "scope-configurations provider is missing the provider configuration"
}

@test "Should fail when NETWORK_LAYER variable is empty" {
	export LAYER_TYPE="network"
	export LAYER_VAR="NETWORK_LAYER"
	export NETWORK_LAYER=""

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ NETWORK_LAYER is not set"
	assert_contains "$output" "build_context did not resolve the network layer"
}

@test "Should fail when DISTRIBUTION_LAYER variable is empty" {
	export LAYER_TYPE="distribution"
	export LAYER_VAR="DISTRIBUTION_LAYER"
	export DISTRIBUTION_LAYER=""

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ DISTRIBUTION_LAYER is not set"
	assert_contains "$output" "build_context did not resolve the distribution layer"
}

# =============================================================================
# Test: Non-existent setup script
# =============================================================================
@test "Should fail when setup script does not exist" {
	export LAYER_TYPE="provider"
	export LAYER_VAR="TOFU_PROVIDER"
	export TOFU_PROVIDER="digitalocean"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ Unknown provider implementation: 'digitalocean'"
	assert_contains "$output" "not a supported provider"
	assert_contains "$output" "deployment/provider/"
}

@test "Should show correct layer type in error for unknown network" {
	export LAYER_TYPE="network"
	export LAYER_VAR="NETWORK_LAYER"
	export NETWORK_LAYER="cloudflare_dns"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ Unknown network implementation: 'cloudflare_dns'"
	assert_contains "$output" "deployment/network/"
}

@test "Should show correct layer type in error for unknown distribution" {
	export LAYER_TYPE="distribution"
	export LAYER_VAR="DISTRIBUTION_LAYER"
	export DISTRIBUTION_LAYER="netlify"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "❌ Unknown distribution implementation: 'netlify'"
	assert_contains "$output" "deployment/distribution/"
}

# =============================================================================
# Test: Successful execution
# =============================================================================
@test "Should execute provider setup script" {
	create_setup_script "provider" "aws" "echo 'AWS provider setup executed'"

	export LAYER_TYPE="provider"
	export LAYER_VAR="TOFU_PROVIDER"
	export TOFU_PROVIDER="aws"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "0"
	assert_contains "$output" "AWS provider setup executed"
}

@test "Should execute network setup script" {
	create_setup_script "network" "route53" "echo 'Route53 network setup executed'"

	export LAYER_TYPE="network"
	export LAYER_VAR="NETWORK_LAYER"
	export NETWORK_LAYER="route53"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "0"
	assert_contains "$output" "Route53 network setup executed"
}

@test "Should execute distribution setup script" {
	create_setup_script "distribution" "cloudfront" "echo 'CloudFront distribution setup executed'"

	export LAYER_TYPE="distribution"
	export LAYER_VAR="DISTRIBUTION_LAYER"
	export DISTRIBUTION_LAYER="cloudfront"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "0"
	assert_contains "$output" "CloudFront distribution setup executed"
}

# =============================================================================
# Test: Environment variable propagation (source, not subprocess)
# =============================================================================
@test "Should propagate TOFU_VARIABLES changes from setup script" {
	export TOFU_VARIABLES='{}'
	create_setup_script "provider" "aws" \
		'TOFU_VARIABLES=$(echo "$TOFU_VARIABLES" | jq '"'"'. + {test_key: "test_value"}'"'"')'

	export LAYER_TYPE="provider"
	export LAYER_VAR="TOFU_PROVIDER"
	export TOFU_PROVIDER="aws"

	source "$SCRIPT_PATH"

	local actual=$(echo "$TOFU_VARIABLES" | jq -r '.test_key')
	assert_equal "$actual" "test_value"
}

@test "Should propagate MODULES_TO_USE changes from setup script" {
	export MODULES_TO_USE=""
	create_setup_script "network" "route53" \
		'MODULES_TO_USE="my/module/path"'

	export LAYER_TYPE="network"
	export LAYER_VAR="NETWORK_LAYER"
	export NETWORK_LAYER="route53"

	source "$SCRIPT_PATH"

	assert_equal "$MODULES_TO_USE" "my/module/path"
}

@test "Should propagate TOFU_INIT_VARIABLES changes from setup script" {
	export TOFU_INIT_VARIABLES=""
	create_setup_script "provider" "aws" \
		'TOFU_INIT_VARIABLES="$TOFU_INIT_VARIABLES -backend-config=bucket=my-bucket"'

	export LAYER_TYPE="provider"
	export LAYER_VAR="TOFU_PROVIDER"
	export TOFU_PROVIDER="aws"

	source "$SCRIPT_PATH"

	assert_contains "$TOFU_INIT_VARIABLES" "-backend-config=bucket=my-bucket"
}

# =============================================================================
# Test: Setup script failure propagation
# =============================================================================
@test "Should propagate non-zero exit code from setup script" {
	create_setup_script "provider" "aws" "echo 'Setup failed'; exit 1"

	export LAYER_TYPE="provider"
	export LAYER_VAR="TOFU_PROVIDER"
	export TOFU_PROVIDER="aws"

	run source "$SCRIPT_PATH"

	assert_equal "$status" "1"
	assert_contains "$output" "Setup failed"
}
