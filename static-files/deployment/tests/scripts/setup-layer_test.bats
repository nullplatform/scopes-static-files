#!/usr/bin/env bats
# =============================================================================
# Unit tests for setup-layer script
#
# Requirements:
#   - bats-core: brew install bats-core
#
# Run tests:
#   bats tests/scripts/setup-layer_test.bats
# =============================================================================

setup() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
	PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"

	source "$PROJECT_ROOT/testing/assertions.sh"

	# The generator derives DEPLOYMENT_DIR from its own location, so copying it
	# into a temporary scripts/ directory sandboxes every file it writes.
	SANDBOX_DIR=$(mktemp -d)
	mkdir -p "$SANDBOX_DIR/scripts"
	cp "$PROJECT_DIR/scripts/setup-layer" "$SANDBOX_DIR/scripts/setup-layer"
	chmod +x "$SANDBOX_DIR/scripts/setup-layer"

	SCRIPT_PATH="$SANDBOX_DIR/scripts/setup-layer"
}

teardown() {
	if [ -n "${SANDBOX_DIR:-}" ] && [ -d "$SANDBOX_DIR" ]; then
		rm -rf "$SANDBOX_DIR"
	fi
}

# =============================================================================
# Tofu test placement
# =============================================================================

@test "Should write the tofu test next to the module it exercises" {
	run "$SCRIPT_PATH" --type distribution --name akamai

	assert_equal "$status" "0"
	# run_tofu_tests.sh runs `tofu test` from the directory holding the
	# .tftest.hcl file, so it must live alongside the .tf files.
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/modules/akamai.tftest.hcl"
}

@test "Should not leave a stray tofu test under tests/" {
	run "$SCRIPT_PATH" --type distribution --name akamai

	assert_equal "$status" "0"
	assert_file_not_exists "$SANDBOX_DIR/tests/distribution/akamai/akamai.tftest.hcl"
}

@test "Should create the BATS test directory for the new layer" {
	run "$SCRIPT_PATH" --type network --name cloudflare

	assert_equal "$status" "0"
	assert_directory_exists "$SANDBOX_DIR/tests/network/cloudflare"
}

# =============================================================================
# Module scaffolding
# =============================================================================

@test "Should create the setup script and the five module files" {
	run "$SCRIPT_PATH" --type distribution --name akamai

	assert_equal "$status" "0"
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/setup"
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/modules/main.tf"
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/modules/variables.tf"
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/modules/locals.tf"
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/modules/outputs.tf"
	assert_file_exists "$SANDBOX_DIR/distribution/akamai/modules/test_locals.tf"
}

@test "Should make the generated setup script executable" {
	run "$SCRIPT_PATH" --type distribution --name akamai

	assert_equal "$status" "0"
	if [ ! -x "$SANDBOX_DIR/distribution/akamai/setup" ]; then
		echo "Expected the generated setup script to be executable"
		return 1
	fi
}

@test "Should normalize the layer name to underscores" {
	run "$SCRIPT_PATH" --type distribution --name Blob-CDN

	assert_equal "$status" "0"
	assert_directory_exists "$SANDBOX_DIR/distribution/blob_cdn"
	assert_file_exists "$SANDBOX_DIR/distribution/blob_cdn/modules/blob_cdn.tftest.hcl"
}

# =============================================================================
# Argument handling
# =============================================================================

@test "Should reject an unknown layer type" {
	run "$SCRIPT_PATH" --type storage --name whatever

	assert_equal "$status" "1"
	assert_contains "$output" "Invalid layer type"
}

@test "Should refuse to overwrite an existing layer" {
	run "$SCRIPT_PATH" --type distribution --name akamai
	assert_equal "$status" "0"

	run "$SCRIPT_PATH" --type distribution --name akamai

	assert_equal "$status" "1"
	assert_contains "$output" "already exists"
}
