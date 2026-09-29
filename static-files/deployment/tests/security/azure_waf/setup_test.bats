#!/usr/bin/env bats
# =============================================================================
# Unit tests for security/azure_waf/setup script
#
# Run tests:
#   bats tests/security/azure_waf/setup_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/security/azure_waf/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  AZURE_MOCKS_DIR="$RESOURCES_DIR/azure_mocks"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export PATH="$AZURE_MOCKS_DIR:$PATH"
  set_az_mock "$AZURE_MOCKS_DIR/waf_policy/success.json" 0

  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7"},
    "providers": {
      "scope-configurations": {
        "provider": {
          "azure_subscription_id": "00000000-0000-0000-0000-000000000000",
          "azure_resource_group": "my-resource-group"
        },
        "security": {
          "azure_security": "azure_waf",
          "azure_waf_policy_name": "sharedwaf"
        }
      }
    }
  }'

  export TOFU_VARIABLES='{
    "application_slug": "automation"
  }'

  export MODULES_TO_USE=""
}

run_azure_waf_setup() {
  source "$SCRIPT_PATH"
}

@test "Should read the WAF policy name from the scope configuration" {
  run_azure_waf_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.security_waf_policy_name')" "sharedwaf"
}

@test "Should default the WAF policy resource group to the provider resource group" {
  run_azure_waf_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.security_waf_policy_resource_group')" "my-resource-group"
}

@test "Should prefer an explicit WAF policy resource group" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].security.azure_waf_policy_resource_group = "security-rg"')

  run_azure_waf_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.security_waf_policy_resource_group')" "security-rg"
}

@test "Should fail when the WAF policy name is not configured" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].security.azure_waf_policy_name)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ security.azure_waf_policy_name is not set"
  assert_contains "$output" "💡 Possible causes:"
  assert_contains "$output" "🔧 How to fix:"
  assert_contains "$output" "Or change 'security.azure_security' to 'none' to skip WAF attachment"
}

@test "Should fail with guidance when the WAF policy does not exist" {
  set_az_mock "$AZURE_MOCKS_DIR/waf_policy/not_found.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Front Door WAF policy 'sharedwaf' was not found in resource group 'my-resource-group'"
  assert_contains "$output" "az network front-door waf-policy create"
}

@test "Should fail with a permission hint when the WAF policy cannot be read" {
  set_az_mock "$AZURE_MOCKS_DIR/waf_policy/access_denied.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "🔒 Error: Permission denied when reading the Front Door WAF policy"
  assert_contains "$output" "resource group 'my-resource-group'"
}

@test "Should show the error details on an unexpected failure" {
  set_az_mock "$AZURE_MOCKS_DIR/waf_policy/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Failed to read the Front Door WAF policy"
  assert_contains "$output" "Unknown error fetching the Front Door WAF policy."
}

@test "Should add security variables to TOFU_VARIABLES" {
  run_azure_waf_setup

  local expected='{
  "application_slug": "automation",
  "security_waf_policy_name": "sharedwaf",
  "security_waf_policy_resource_group": "my-resource-group"
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should register the module in MODULES_TO_USE when it's empty" {
  run_azure_waf_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/security/azure_waf/modules"
}

@test "Should append the module to MODULES_TO_USE when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_azure_waf_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/security/azure_waf/modules"
}
