#!/usr/bin/env bats
# =============================================================================
# Unit tests for scripts/resolve_tofu_action
#
# Run tests:
#   bats tests/scripts/resolve_tofu_action_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/scripts/resolve_tofu_action"

  source "$PROJECT_ROOT/testing/assertions.sh"
}

resolve() {
  export STATIC_FILES_PHASE="$1"
  export DISTRIBUTION_LAYER="$2"
  source "$SCRIPT_PATH"
}

@test "scope-apply applies on front-door" {
  resolve scope-apply front-door
  assert_equal "$TOFU_ACTION" "apply"
}

@test "scope-apply skips on cloudfront" {
  resolve scope-apply cloudfront
  assert_equal "$TOFU_ACTION" "skip"
}

@test "scope-delete destroys on front-door" {
  resolve scope-delete front-door
  assert_equal "$TOFU_ACTION" "destroy"
}

@test "scope-delete skips on cloudfront" {
  resolve scope-delete cloudfront
  assert_equal "$TOFU_ACTION" "skip"
}

@test "deployment-apply applies on front-door" {
  resolve deployment-apply front-door
  assert_equal "$TOFU_ACTION" "apply"
}

@test "deployment-apply applies on cloudfront" {
  resolve deployment-apply cloudfront
  assert_equal "$TOFU_ACTION" "apply"
}

@test "deployment-delete skips on front-door" {
  resolve deployment-delete front-door
  assert_equal "$TOFU_ACTION" "skip"
}

@test "deployment-delete destroys on cloudfront" {
  resolve deployment-delete cloudfront
  assert_equal "$TOFU_ACTION" "destroy"
}

@test "fails on an unknown phase" {
  export STATIC_FILES_PHASE="scope-destroy"
  export DISTRIBUTION_LAYER="front-door"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Unknown STATIC_FILES_PHASE 'scope-destroy'"
  assert_contains "$output" "🔧 How to fix:"
}

@test "fails when the phase is not set" {
  unset STATIC_FILES_PHASE
  export DISTRIBUTION_LAYER="front-door"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ STATIC_FILES_PHASE is not set"
}

@test "fails on an unknown distribution" {
  export STATIC_FILES_PHASE="scope-apply"
  export DISTRIBUTION_LAYER="blob-cdn"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Unknown distribution layer 'blob-cdn'"
}
