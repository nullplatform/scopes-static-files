#!/usr/bin/env bats
# =============================================================================
# Consistency tests between the scope-configuration schema and the layer tree
#
# layer_executor resolves a layer implementation by joining the configured
# value straight onto a path: deployment/{layer_type}/{value}/setup. So every
# value the schema offers has to exist as a directory with that exact name.
# A mismatch (an underscore against a hyphen, say) is invisible until the
# first deployment fails with "Unknown implementation".
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq
#
# Run tests:
#   bats tests/specs/layer_selection_test.bats
# =============================================================================

setup() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	DEPLOYMENT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
	MODULE_DIR="$(cd "$DEPLOYMENT_DIR/.." && pwd)"
	PROJECT_ROOT="$(cd "$MODULE_DIR/.." && pwd)"

	source "$PROJECT_ROOT/testing/assertions.sh"

	SCHEMA_FILE="$MODULE_DIR/specs/scope-configuration.json.tpl"
}

# The spec is a Go template, so the {{ ... }} expressions have to be
# neutralized before jq can read it as JSON.
render_schema() {
	sed 's/"{{[^}]*}}"/"PLACEHOLDER"/g' "$SCHEMA_FILE"
}

# Emits one "<layer_type><TAB><value>" row per selectable implementation.
# cloud_provider drives the provider layer; the other three layers use
# "<cloud>_<layer>" fields, which is what the suffix filter picks up.
layer_selections() {
	render_schema | jq -r '
	  (.schema.properties.cloud_provider.oneOf[]? | ["provider", .const]),
	  (["distribution", "network", "security"][] as $layer
	   | .schema.properties[$layer].properties
	   | to_entries[]
	   | select(.key | endswith("_" + $layer))
	   | .value.oneOf[]?
	   | [$layer, .const])
	  | @tsv'
}

@test "Should parse the schema as JSON once templates are neutralized" {
	run bash -c "$(declare -f render_schema); SCHEMA_FILE='$SCHEMA_FILE'; render_schema | jq -e . >/dev/null"

	assert_equal "$status" "0"
}

@test "Should offer at least one implementation per layer" {
	local rows
	rows=$(layer_selections)

	for layer in provider distribution network security; do
		if ! echo "$rows" | grep -q "^${layer}	"; then
			echo "No selectable implementation found for layer '$layer'"
			return 1
		fi
	done
}

@test "Should map every schema layer value to an implementation directory" {
	local failures=""

	while IFS=$'\t' read -r layer value; do
		[ -z "$layer" ] && continue

		if [ ! -d "$DEPLOYMENT_DIR/$layer/$value" ]; then
			failures="${failures}\n  ${layer}/${value} -> directory not found"
		fi
	done <<< "$(layer_selections)"

	if [ -n "$failures" ]; then
		echo "Schema offers implementations that layer_executor cannot resolve:"
		echo -e "$failures"
		echo ""
		echo "Each value must match a directory under deployment/<layer>/ exactly."
		return 1
	fi
}

@test "Should have a setup script in every layer implementation directory" {
	local failures=""

	while IFS=$'\t' read -r layer value; do
		[ -z "$layer" ] && continue

		if [ ! -f "$DEPLOYMENT_DIR/$layer/$value/setup" ]; then
			failures="${failures}\n  ${layer}/${value}/setup -> missing"
		fi
	done <<< "$(layer_selections)"

	if [ -n "$failures" ]; then
		echo "layer_executor sources <layer>/<value>/setup, which is missing for:"
		echo -e "$failures"
		return 1
	fi
}
