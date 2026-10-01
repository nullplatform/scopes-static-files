# Azure Scope Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Azure (`front-door`), create the scope's Front Door resources at `create-scope`, destroy them at `delete-scope`, and make `delete-deployment` a no-op, so a deployment only switches the route's origin path.

**Architecture:** A new step `resolve_tofu_action` turns the workflow's `STATIC_FILES_PHASE` and `DISTRIBUTION_LAYER` into `TOFU_ACTION` (`apply`, `destroy` or `skip`). `layer_executor`, `compose_modules` and `do_tofu` return early on `skip`. The Front Door setup takes the storage account from a new scope configuration attribute in scope phases, where there is no asset, and points the route at a placeholder prefix.

**Tech Stack:** Bash, jq, BATS, OpenTofu, nullplatform workflow engine (`np service workflow exec`).

**Spec:** `docs/design/azure-scope-lifecycle.md`

## Global Constraints

- Azure `front-door` only. `cloudfront` behavior is unchanged: scope workflows do nothing and `delete-deployment` destroys.
- Phases are exactly `scope-apply`, `scope-delete`, `deployment-apply`, `deployment-delete`.
- `STATIC_FILES_PHASE` unset means `deployment-apply` in the Front Door setup (local runs and existing tests keep working).
- New attribute `distribution.azure_assets_storage_account`, env fallback `AZURE_ASSETS_STORAGE_ACCOUNT`: required in scope phases, optional in deployment phases (must match the asset URL's account when set).
- Placeholder blob prefix: `/_not-deployed/<application>-<scope>-<scope_id>` (the scope's `distribution_app_name`).
- Engine semantics (verified 2026-10-01 with `np` 2.10.1): variables a step exports reach every later step without `output:`; a step can overwrite a `configuration:` variable; an including workflow's `configuration:` merges over the included one.
- Script style: `set -euo pipefail`, tabs in `deployment/scripts/*`, two spaces in layer `setup` files, and the repository's `❌` / `💡 Possible causes:` / `🔧 How to fix:` error blocks.
- No `Co-Authored-By` trailers. Conventional commits.

## Review Focus

- A scope created before this change has no `STATIC_FILES_PHASE` history: its next `start-blue-green` must still apply normally (covered: the `deployment-apply` row and the unset-phase default).
- An installation that never sets `azure_assets_storage_account` must keep deploying (covered: deployment phase with the attribute absent).
- `delete-deployment` on Azure must not touch the state at all, not even `tofu init` (covered: `do_tofu` skip test asserts no `tofu` call).
- An AWS `create-scope` must not run the CloudFront setup, which requires an asset (covered: `scope-apply` + `cloudfront` → `skip`, and the `layer_executor` skip test).
- A typo in `STATIC_FILES_PHASE` must fail loudly instead of defaulting to a destroy (covered: unknown phase test).

---

### Task 1: `resolve_tofu_action`

**Files:**
- Create: `static-files/deployment/scripts/resolve_tofu_action`
- Test: `static-files/deployment/tests/scripts/resolve_tofu_action_test.bats`

**Interfaces:**
- Consumes: `STATIC_FILES_PHASE`, `DISTRIBUTION_LAYER` (exported by `build_context`).
- Produces: exported `TOFU_ACTION` ∈ {`apply`, `destroy`, `skip`}.

- [ ] **Step 1: Write the failing test**

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit MODULE=static-files 2>&1 | grep -E "resolve_tofu_action|tests,"`
Expected: FAIL (`resolve_tofu_action: No such file or directory`).

- [ ] **Step 3: Write the implementation**

```bash
#!/bin/bash
# =============================================================================
# Resolve TOFU_ACTION for this workflow
#
# Scope and deployment workflows are shared by every cloud. Each one declares
# its phase (STATIC_FILES_PHASE); this step maps phase and distribution layer
# to the OpenTofu action. On Azure (front-door) the scope owns the Front Door
# resources: create/update apply them, delete destroys them, and deleting a
# deployment changes nothing. On AWS (cloudfront) the first deployment still
# owns everything, so scope actions skip and deleting a deployment destroys.
#
#   phase              front-door  cloudfront
#   scope-apply        apply       skip
#   scope-delete       destroy     skip
#   deployment-apply   apply       apply
#   deployment-delete  skip        destroy
# =============================================================================

set -euo pipefail

if [ -z "${STATIC_FILES_PHASE:-}" ]; then
	echo "   ❌ STATIC_FILES_PHASE is not set" >&2
	echo "  🔧 How to fix: declare STATIC_FILES_PHASE in the workflow configuration" >&2
	exit 1
fi

case "${DISTRIBUTION_LAYER:-}" in
front-door | cloudfront) ;;
*)
	echo "   ❌ Unknown distribution layer '${DISTRIBUTION_LAYER:-}'"
	echo ""
	echo "  💡 Possible causes:"
	echo "    • build_context did not run before this step"
	echo "    • A new distribution layer was added without a lifecycle mapping"
	echo ""
	echo "  🔧 How to fix:"
	echo "    • Add the layer to deployment/scripts/resolve_tofu_action"
	echo ""
	exit 1
	;;
esac

case "$STATIC_FILES_PHASE:$DISTRIBUTION_LAYER" in
scope-apply:front-door) TOFU_ACTION="apply" ;;
scope-apply:cloudfront) TOFU_ACTION="skip" ;;
scope-delete:front-door) TOFU_ACTION="destroy" ;;
scope-delete:cloudfront) TOFU_ACTION="skip" ;;
deployment-apply:*) TOFU_ACTION="apply" ;;
deployment-delete:front-door) TOFU_ACTION="skip" ;;
deployment-delete:cloudfront) TOFU_ACTION="destroy" ;;
*)
	echo "   ❌ Unknown STATIC_FILES_PHASE '$STATIC_FILES_PHASE'"
	echo ""
	echo "  💡 Possible causes:"
	echo "    • A workflow declares a phase this script does not know"
	echo ""
	echo "  🔧 How to fix:"
	echo "    • Use one of: scope-apply, scope-delete, deployment-apply, deployment-delete"
	echo ""
	exit 1
	;;
esac

echo "   ✅ phase=$STATIC_FILES_PHASE distribution=$DISTRIBUTION_LAYER tofu_action=$TOFU_ACTION"

export TOFU_ACTION
```

Make it executable: `chmod +x static-files/deployment/scripts/resolve_tofu_action`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-unit MODULE=static-files 2>&1 | grep -E "resolve_tofu_action|tests,"`
Expected: the 11 new tests pass; total failures 0.

- [ ] **Step 5: Commit**

```bash
git add static-files/deployment/scripts/resolve_tofu_action static-files/deployment/tests/scripts/resolve_tofu_action_test.bats
git commit -m "feat(scope): resolve the tofu action from workflow phase and distribution"
```

### Task 2: `skip` in `layer_executor`, `compose_modules` and `do_tofu`

**Files:**
- Modify: `static-files/deployment/scripts/layer_executor` (after `set -euo pipefail`, line 23)
- Modify: `static-files/deployment/scripts/compose_modules` (before the validation, line 17)
- Modify: `static-files/deployment/scripts/do_tofu` (after `set -eou pipefail`, line 3)
- Test: `static-files/deployment/tests/scripts/skip_test.bats`

**Interfaces:**
- Consumes: `TOFU_ACTION` from Task 1.
- Produces: no side effects when `TOFU_ACTION=skip` (no layer setup, no copied modules, no `tofu` call).

- [ ] **Step 1: Write the failing test**

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit MODULE=static-files 2>&1 | grep -E "skip_test|Skipping|tests,"`
Expected: FAIL (the scripts do not know `skip`; `layer_executor` fails on the missing `cloudfront` setup in the temp `SERVICE_PATH`, `compose_modules` fails on the empty `MODULES_TO_USE`).

- [ ] **Step 3: Write the implementation**

`layer_executor`, right after `set -euo pipefail`:

```bash
if [ "${TOFU_ACTION:-}" = "skip" ]; then
	echo "   ⏭️  Skipping ${LAYER_TYPE:-the} layer: nothing to do in phase ${STATIC_FILES_PHASE:-unknown}"
	return 0 2>/dev/null || exit 0
fi
```

`compose_modules`, before `echo "🔍 Validating module composition configuration..."`:

```bash
if [ "${TOFU_ACTION:-}" = "skip" ]; then
  echo "⏭️  Skipping module composition: nothing to do in phase ${STATIC_FILES_PHASE:-unknown}"
  return 0 2>/dev/null || exit 0
fi
```

`do_tofu`, right after `set -eou pipefail`:

```bash
if [ "${TOFU_ACTION:-}" = "skip" ]; then
	echo "⏭️  Skipping OpenTofu: nothing to do in phase ${STATIC_FILES_PHASE:-unknown}"
	exit 0
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-unit MODULE=static-files 2>&1 | grep -E "skip_test|tests,"`
Expected: 3 new tests pass; failures 0.

- [ ] **Step 5: Commit**

```bash
git add static-files/deployment/scripts/layer_executor static-files/deployment/scripts/compose_modules static-files/deployment/scripts/do_tofu static-files/deployment/tests/scripts/skip_test.bats
git commit -m "feat(scope): skip layers, modules and tofu when the phase has nothing to do"
```

### Task 3: Front Door setup without an asset

**Files:**
- Modify: `static-files/deployment/distribution/front-door/setup:11-67` (asset block)
- Modify: `static-files/specs/scope-configuration.json.tpl` (new property after `azure_front_door_endpoint`, line 287; new UI control next to `azure_front_door_endpoint`)
- Test: `static-files/deployment/tests/distribution/front-door/setup_test.bats`

**Interfaces:**
- Consumes: `STATIC_FILES_PHASE` (unset = `deployment-apply`), `CONTEXT.providers["scope-configurations"].distribution.azure_assets_storage_account`, `AZURE_ASSETS_STORAGE_ACCOUNT`.
- Produces: unchanged `TOFU_VARIABLES` keys (`distribution_storage_account`, `distribution_container_name`, `distribution_blob_prefix`, ...).

- [ ] **Step 1: Write the failing tests** (append to `setup_test.bats`)

```bash
@test "Should use the configured storage account and the placeholder prefix in scope phases" {
  export STATIC_FILES_PHASE="scope-apply"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.asset) | .providers["scope-configurations"].distribution.azure_assets_storage_account = "mystaticstorage"')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_storage_account')" "mystaticstorage"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')" '$web'
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')" "/_not-deployed/automation-development-tools-7"
}

@test "Should read the assets storage account from AZURE_ASSETS_STORAGE_ACCOUNT in scope phases" {
  export STATIC_FILES_PHASE="scope-delete"
  export AZURE_ASSETS_STORAGE_ACCOUNT="envstorage"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.asset)')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_storage_account')" "envstorage"
}

@test "Should fail in scope phases when the assets storage account is not configured" {
  export STATIC_FILES_PHASE="scope-apply"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.asset)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_assets_storage_account is missing"
  assert_contains "$output" "distribution.azure_assets_storage_account"
}

@test "Should keep deploying when the assets storage account is not configured" {
  export STATIC_FILES_PHASE="deployment-apply"

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_storage_account')" "mystaticstorage"
}

@test "Should fail when the asset is in a different storage account than the configured one" {
  export STATIC_FILES_PHASE="deployment-apply"
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_assets_storage_account = "otherstorage"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ The asset is in storage account 'mystaticstorage', but the scope serves 'otherstorage'"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-unit MODULE=static-files 2>&1 | grep -E "front-door|✗|tests,"`
Expected: the 5 new tests fail (scope phases still parse the missing asset URL `null` and exit 1; the mismatch is not detected).

- [ ] **Step 3: Write the implementation**

In `setup`, replace line 14 (`asset_url=...`) and the block at lines 19-48 with:

```bash
phase="${STATIC_FILES_PHASE:-deployment-apply}"

distribution_app_name="$application_slug-$scope_slug-$scope_id"
echo "   ✅ app_name=$distribution_app_name"

# Storage account the scope serves from. Required when the scope creates or
# destroys its resources (no asset then); optional on deployments, where it
# guards against an asset uploaded to another account.
assets_storage_account=$(get_config_value \
  --provider '.providers["scope-configurations"].distribution.azure_assets_storage_account' \
  --env AZURE_ASSETS_STORAGE_ACCOUNT)

if [[ "$phase" == scope-* ]]; then
  # =============================================================================
  # Scope phase: no asset yet. The route points at a prefix with no blobs, so
  # the domain answers 404 until the first deployment, and never serves another
  # application's bundles from the shared container.
  # =============================================================================
  if [ -z "$assets_storage_account" ]; then
    echo ""
    echo "   ❌ azure_assets_storage_account is missing"
    echo ""
    echo "  💡 Possible causes:"
    echo "    • The scope configuration predates scope-level Front Door resources"
    echo ""
    echo "  🔧 How to fix:"
    echo "    • Set distribution.azure_assets_storage_account in the scope-configurations provider"
    echo "    • Or set AZURE_ASSETS_STORAGE_ACCOUNT in the agent"
    echo ""
    exit 1
  fi
  distribution_storage_account="$assets_storage_account"
  distribution_container_name="\$web"
  distribution_blob_prefix="/_not-deployed/$distribution_app_name"
else
  asset_url=$(echo "$CONTEXT" | jq -r .asset.url)
  # (existing block, unchanged: parse https://<account>.blob.core.windows.net/<container>/<prefix>)
fi
```

Keep the existing asset-parsing block (current lines 19-48) verbatim inside the `else` branch, re-indented by two spaces, and delete the old `distribution_app_name` lines (16-17) since they move above. After the existing `$web` container check (current lines 50-63), add:

```bash
if [ -n "$assets_storage_account" ] && [ "$assets_storage_account" != "$distribution_storage_account" ]; then
  echo ""
  echo "   ❌ The asset is in storage account '$distribution_storage_account', but the scope serves '$assets_storage_account'"
  echo ""
  echo "  💡 Possible causes:"
  echo "    • CI uploaded the bundle to a different storage account"
  echo ""
  echo "  🔧 How to fix:"
  echo "    • Upload the bundle to '$assets_storage_account', or update distribution.azure_assets_storage_account"
  echo ""
  exit 1
fi
```

In `specs/scope-configuration.json.tpl`, add after the `azure_front_door_endpoint` property:

```json
          "azure_assets_storage_account": {
            "type": "string",
            "title": "Assets Storage Account",
            "description": "Storage account (static website enabled) that CI uploads bundles to. The scope creates its Front Door origin on it when the scope is created, before any deployment.",
            "pattern": "^([a-z0-9]{3,24})?$"
          },
```

and a UI control, next to the `azure_front_door_endpoint` one, with the same `HIDE` rule on `cloud_provider != azure`, scoped to `#/properties/distribution/properties/azure_assets_storage_account`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-unit MODULE=static-files 2>&1 | tail -3` and `bats static-files/deployment/tests/specs/layer_selection_test.bats`
Expected: all tests pass, including the 34 existing Front Door setup tests (no `STATIC_FILES_PHASE` = deployment) and the schema consistency tests.

- [ ] **Step 5: Commit**

```bash
git add static-files/deployment/distribution/front-door/setup static-files/deployment/tests/distribution/front-door/setup_test.bats static-files/specs/scope-configuration.json.tpl
git commit -m "feat(distribution): front door setup without an asset in scope phases"
```

### Task 4: Wire the phases into the workflows

**Files:**
- Modify: `static-files/deployment/workflows/initial.yaml` (add `STATIC_FILES_PHASE: "deployment-apply"`, add the `resolve_tofu_action` step after `build_context`)
- Modify: `static-files/deployment/workflows/delete.yaml` (`STATIC_FILES_PHASE: "deployment-delete"` instead of `TOFU_ACTION: "destroy"`)
- Modify: `static-files/scope/workflows/create.yaml`, `update.yaml` (`scope-apply`), `delete.yaml` (`scope-delete`)
- Test: `static-files/deployment/tests/specs/workflow_phases_test.bats`

**Interfaces:**
- Consumes: `resolve_tofu_action` (Task 1), skip handling (Task 2), Front Door scope phases (Task 3).
- Produces: the action table of the spec, end to end.

- [ ] **Step 1: Write the failing test**

```bash
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

@test "scope create and update apply, scope delete destroys" {
  assert_equal "$(phase_of "$STATIC_DIR/scope/workflows/create.yaml")" "scope-apply"
  assert_equal "$(phase_of "$STATIC_DIR/scope/workflows/update.yaml")" "scope-apply"
  assert_equal "$(phase_of "$STATIC_DIR/scope/workflows/delete.yaml")" "scope-delete"
}

@test "resolve_tofu_action runs right after build_context" {
  run grep -n -E 'name: (build_context|resolve_tofu_action|setup_provider_layer)' "$STATIC_DIR/deployment/workflows/initial.yaml"
  order=$(echo "$output" | sed -E 's/.*name: //' | paste -sd, -)
  assert_equal "$order" "build_context,resolve_tofu_action,setup_provider_layer"
}

@test "scope workflows run the deployment steps" {
  for wf in create update delete; do
    run grep -F '$SERVICE_PATH/deployment/workflows/initial.yaml' "$STATIC_DIR/scope/workflows/$wf.yaml"
    assert_equal "$status" "0"
  done
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats static-files/deployment/tests/specs/workflow_phases_test.bats`
Expected: FAIL (no workflow declares `STATIC_FILES_PHASE`).

- [ ] **Step 3: Write the implementation**

`deployment/workflows/initial.yaml`: under `configuration:` add `STATIC_FILES_PHASE: "deployment-apply"`; after the `build_context` step add:

```yaml
  - name: resolve_tofu_action
    type: script
    file: "$SERVICE_PATH/deployment/scripts/resolve_tofu_action"
    output:
      - name: TOFU_ACTION
        type: environment
```

`deployment/workflows/delete.yaml`:

```yaml
include:
  - "$SERVICE_PATH/deployment/workflows/initial.yaml"
configuration:
  STATIC_FILES_PHASE: "deployment-delete"
```

`scope/workflows/create.yaml`:

```yaml
# Azure (front-door): creates the scope's Front Door resources, with the route
# pointing at a placeholder until the first deployment. AWS (cloudfront): no-op,
# the first deployment still creates the distribution.
include:
  - "$SERVICE_PATH/deployment/workflows/initial.yaml"
configuration:
  STATIC_FILES_PHASE: "scope-apply"
```

`scope/workflows/update.yaml`: same as `create.yaml`.

`scope/workflows/delete.yaml`:

```yaml
# Azure (front-door): destroys the scope's Front Door resources. AWS
# (cloudfront): no-op, deleting the deployment destroys the distribution.
include:
  - "$SERVICE_PATH/deployment/workflows/initial.yaml"
configuration:
  STATIC_FILES_PHASE: "scope-delete"
```

- [ ] **Step 4: Verify the resolved workflows with the engine**

Run, for each of the five workflows:
`SERVICE_PATH=$PWD/static-files np service workflow exec --dry-run --workflow static-files/scope/workflows/create.yaml`
Expected: the printed workflow has `STATIC_FILES_PHASE` set to the workflow's phase and the step order `assume role, build_context, resolve_tofu_action, setup_provider_layer, ...`.

Then run `bats static-files/deployment/tests/specs/workflow_phases_test.bats` and `make test-unit`.
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add static-files/deployment/workflows static-files/scope/workflows static-files/deployment/tests/specs/workflow_phases_test.bats
git commit -m "feat(scope)!: front door resources follow the scope lifecycle on azure

BREAKING CHANGE: on Azure, create-scope now creates the Front Door resources
and needs distribution.azure_assets_storage_account; delete-scope destroys
them and delete-deployment no longer destroys anything."
```

### Task 5: Azure integration lifecycle test

**Files:**
- Modify: `static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/lifecycle_test.bats`

**Interfaces:**
- Consumes: the workflows of Task 4.

- [ ] **Step 1: Rewrite the lifecycle around the scope**

Replace the single `initial.yaml` → `delete.yaml` flow (lines 89 and 115) with four steps, each in its own `@test` sharing the seeded resources:

1. `create-scope`: `override_context "asset" "null"`, set `azure_assets_storage_account = TEST_DISTRIBUTION_STORAGE_ACCOUNT` in the scope configuration, `export STATIC_FILES_PHASE=scope-apply`, `run_workflow "static-files/scope/workflows/create.yaml"`. Assert the route exists with origin path `/_not-deployed/${TEST_DISTRIBUTION_APP_NAME}`, the custom domain and the CNAME exist, and `PATCH /scope/7` was called.
2. `start-initial`: reload the context with the asset, `run_workflow "static-files/deployment/workflows/initial.yaml"`. Assert the route's origin path is `${TEST_DISTRIBUTION_ORIGIN_PATH}` and a purge was recorded.
3. `delete-deployment`: `run_workflow "static-files/deployment/workflows/delete.yaml"`. Assert the output contains `⏭️  Skipping OpenTofu` and the route, domain and CNAME still exist.
4. `delete-scope`: drop the asset, `run_workflow "static-files/scope/workflows/delete.yaml"`. Assert the scope's resources are gone and the shared profile, endpoint, zone and storage account remain (the existing assertions of the old destroy step).

Use the existing helpers in `front_door_assertions.bash` and `dns_assertions.bash`; the route lookup by name is `${TEST_DISTRIBUTION_APP_NAME}`.

- [ ] **Step 2: Run it**

Run: `make test-integration MODULE=azure_frontdoor_azuredns`
Expected: 4 tests pass. Requires Docker with the `testing/` mocks; if Docker is not available, record that it was not run in the PR description.

- [ ] **Step 3: Run the AWS lifecycle unchanged**

Run: `make test-integration MODULE=aws_cloudfront_route53`
Expected: passes unchanged (or record it was not run, as above).

- [ ] **Step 4: Commit**

```bash
git add static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/lifecycle_test.bats
git commit -m "test(integration): azure lifecycle runs through the scope workflows"
```

### Task 6: Documentation

**Files:**
- Modify: `docs/design/azure-scope-lifecycle.md` (status line; attribute optional on deployments; placeholder prefix; no tftest change)
- Modify: `static-files/README.md` (Azure configuration table: new `distribution.azure_assets_storage_account` row; a "Scope lifecycle on Azure" paragraph replacing "several minutes on the first deployment")

- [ ] **Step 1: Update the spec and the README**

Spec: `Status: approved 2026-10-01, implemented on branch feat/azure-scope-lifecycle.`; in "Inputs without an asset", the attribute is required in scope phases and optional on deployments (validated when set); the placeholder is `/_not-deployed/<application>-<scope>-<scope_id>`; drop the `front-door.tftest.hcl` bullet from Testing.

README: add the attribute to the Front Door configuration table (`distribution.azure_assets_storage_account` | required to create scopes | storage account CI uploads to) and replace the first-deployment note at line ~195 with: on Azure the scope's Front Door resources are created with the scope (15–37 minutes, the scope stays `creating`); deployments only switch the origin path.

- [ ] **Step 2: Lint**

Run: `shellcheck static-files/deployment/scripts/resolve_tofu_action static-files/deployment/scripts/layer_executor static-files/deployment/scripts/do_tofu static-files/deployment/distribution/front-door/setup`
Expected: no findings.

- [ ] **Step 3: Commit**

```bash
git add docs/design/azure-scope-lifecycle.md static-files/README.md
git commit -m "docs: azure scope lifecycle and the assets storage account"
```

## Outside this repository

After the release: set `azure_assets_storage_account` in every Azure environment's scope configuration (for Farmácias São João, `nullplatform-bindings/main.tf` `static_files_attributes.distribution`, value `stnpfsjassets`), bump the scope definition, and validate the three risks of the spec on the first new scope.
