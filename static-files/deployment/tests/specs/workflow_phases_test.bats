#!/usr/bin/env bats
# =============================================================================
# Every workflow that runs tofu declares its lifecycle phase, and the resolved
# workflow (np service workflow exec --dry-run) runs resolve_tofu_action
# before any layer.
#
# Run tests:
#   bats tests/specs/workflow_phases_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  STATIC_DIR="$(cd "$PROJECT_DIR/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"
}

phase_of() {
  grep -E '^\s*STATIC_FILES_PHASE:' "$1" | sed -E 's/.*: *"?([a-z-]+)"?.*/\1/'
}

@test "initial deployment applies" {
  assert_equal "$(phase_of "$STATIC_DIR/deployment/workflows/initial.yaml")" "deployment-apply"
}

@test "deleting a deployment declares deployment-delete and no longer forces destroy" {
  assert_equal "$(phase_of "$STATIC_DIR/deployment/workflows/delete.yaml")" "deployment-delete"
  run grep -E 'TOFU_ACTION:' "$STATIC_DIR/deployment/workflows/delete.yaml"
  assert_equal "$status" "1"
}

@test "scope create applies, scope delete destroys" {
  assert_equal "$(phase_of "$STATIC_DIR/scope/workflows/create.yaml")" "scope-apply"
  assert_equal "$(phase_of "$STATIC_DIR/scope/workflows/delete.yaml")" "scope-delete"
}

@test "scope update stays a no-op: scope-apply would move a live route back to the placeholder" {
  run grep -F '$SERVICE_PATH/deployment/workflows/initial.yaml' "$STATIC_DIR/scope/workflows/update.yaml"
  assert_equal "$status" "1"
  run grep -F '$SERVICE_PATH/no_op' "$STATIC_DIR/scope/workflows/update.yaml"
  assert_equal "$status" "0"
}

@test "resolve_tofu_action runs right after build_context, before assume role and the layers" {
  run grep -n -E 'name: (assume role|build_context|resolve_tofu_action|setup_provider_layer)' "$STATIC_DIR/deployment/workflows/initial.yaml"
  order=$(echo "$output" | sed -E 's/.*name: //' | paste -sd, -)
  assert_equal "$order" "build_context,resolve_tofu_action,assume role,setup_provider_layer"
}

@test "scope workflows run the deployment steps" {
  for wf in create delete; do
    run grep -F '$SERVICE_PATH/deployment/workflows/initial.yaml' "$STATIC_DIR/scope/workflows/$wf.yaml"
    assert_equal "$status" "0"
  done
}
