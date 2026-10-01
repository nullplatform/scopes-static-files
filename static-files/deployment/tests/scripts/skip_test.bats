#!/usr/bin/env bats
# =============================================================================
# TOFU_ACTION=skip short-circuits the layer, compose and tofu steps
#
# Run tests:
#   bats tests/scripts/skip_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPTS_DIR="$PROJECT_DIR/scripts"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export TOFU_ACTION="skip"
  export SERVICE_PATH="$BATS_TEST_TMPDIR/service"
  export TOFU_MODULE_DIR="$BATS_TEST_TMPDIR/modules"

  # A tofu that records every call, to prove it is never invoked.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tofu" <<'EOF'
#!/bin/bash
echo "$*" >> "$BATS_TEST_TMPDIR/tofu_calls"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/tofu"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "layer_executor skips the layer setup" {
  export LAYER_TYPE="distribution"
  export LAYER_VAR="DISTRIBUTION_LAYER"
  export DISTRIBUTION_LAYER="cloudfront"

  run source "$SCRIPTS_DIR/layer_executor"

  assert_equal "$status" "0"
  assert_contains "$output" "⏭️  Skipping distribution layer"
}

@test "compose_modules copies nothing" {
  export MODULES_TO_USE=""

  run source "$SCRIPTS_DIR/compose_modules"

  assert_equal "$status" "0"
  assert_contains "$output" "⏭️  Skipping module composition"
  [ ! -d "$TOFU_MODULE_DIR" ]
}

@test "do_tofu never calls tofu" {
  export TOFU_VARIABLES='{}'
  export TOFU_INIT_VARIABLES=""
  mkdir -p "$TOFU_MODULE_DIR"

  run bash "$SCRIPTS_DIR/do_tofu"

  assert_equal "$status" "0"
  assert_contains "$output" "⏭️  Skipping OpenTofu"
  [ ! -f "$BATS_TEST_TMPDIR/tofu_calls" ]
}
