#!/usr/bin/env bats
# =============================================================================
# Unit tests for instance/build_context
#
# Resolves the name the distribution layer gives a scope's distribution, which
# is what list_instances matches on.
#
# Run tests:
#   bats tests/instance/build_context_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/instance/build_context"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7"}
  }'
}

# =============================================================================
# Test: The distribution name is built the same way the layer names it
# =============================================================================
@test "Should name the distribution after the application, scope and scope id" {
  source "$SCRIPT_PATH"

  assert_equal "$DISTRIBUTION_APP_NAME" "automation-development-tools-7"
}

@test "Should fail when the scope is missing from the context" {
  export CONTEXT='{"application": {"slug": "automation"}}'

  run bash -c "source '$SCRIPT_PATH'"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not resolve the scope from the context"
  assert_contains "$output" "🔧 How to fix:"
}
