#!/usr/bin/env bats
# =============================================================================
# Unit tests for network/cloudflare/setup script
#
# Requirements:
#   - bats-core: brew install bats-core
#   - jq: brew install jq
#
# Run tests:
#   bats tests/network/cloudflare/setup_test.bats
# =============================================================================

# Setup - runs before each test
setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/network/cloudflare/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  CLOUDFLARE_MOCKS_DIR="$RESOURCES_DIR/cloudflare_mocks"
  NP_MOCKS_DIR="$RESOURCES_DIR/np_mocks"

  # Load shared test utilities
  source "$PROJECT_ROOT/testing/assertions.sh"

  # Add mock curl and np to PATH (must be first)
  export PATH="$CLOUDFLARE_MOCKS_DIR:$NP_MOCKS_DIR:$PATH"

  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7"},
    "providers": {
      "scope-configurations": {
        "network": {
          "cloudflare_zone_id": "023e105f4ecef8ad9ca31a8372d0c353"
        }
      }
    }
  }'

  # Initialize TOFU_VARIABLES with existing keys to verify script merges (not replaces)
  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export MODULES_TO_USE=""
  export CLOUDFLARE_API_TOKEN="test-token-value"
  unset TOFU_ACTION

  # Default mocks: the zone exists and the scope patch succeeds
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/success.json"
  export NP_MOCK_RESPONSE="$NP_MOCKS_DIR/scope/patch/success.json"
  export NP_MOCK_EXIT_CODE="0"

  export CURL_MOCK_ARGS_FILE="$BATS_TEST_TMPDIR/curl_args"
  export CURL_MOCK_STDIN_FILE="$BATS_TEST_TMPDIR/curl_stdin"
}

# =============================================================================
# Helper functions
# =============================================================================
run_cloudflare_setup() {
  source "$SCRIPT_PATH"
}

# Usage: set_curl_mock "<mock_file>" [http_code] [exit_code]
set_curl_mock() {
  export CURL_MOCK_RESPONSE="$1"
  export CURL_MOCK_HTTP_CODE="${2:-200}"
  export CURL_MOCK_EXIT_CODE="${3:-0}"
}

# =============================================================================
# Test: Required configuration
# =============================================================================
@test "Should fail when cloudflare_zone_id is not present in context" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].network.cloudflare_zone_id)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ cloudflare_zone_id is not configured"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Set 'network.cloudflare_zone_id' in the scope-configurations provider"
}

@test "Should fail when CLOUDFLARE_API_TOKEN is not set" {
  unset CLOUDFLARE_API_TOKEN

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ CLOUDFLARE_API_TOKEN is not set"
  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    • Expose CLOUDFLARE_API_TOKEN to the scope's worker from a secret"
  assert_contains "$output" "    • The token needs 'Zone:Read' and 'DNS:Edit' on the zone"
}

@test "Should fail when cloudflare_proxied is not a boolean" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].network.cloudflare_proxied = "yes"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ cloudflare_proxied must be true or false, got 'yes'"
}

@test "Should reject a zone ID that is not 32 hexadecimal characters" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].network.cloudflare_zone_id = "example.com"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ cloudflare_zone_id is not a valid Cloudflare zone ID"
  assert_contains "$output" "    • A zone name was configured instead of the zone ID"
}

@test "Should reject a zone ID that tries to change the request path before calling the API" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].network.cloudflare_zone_id = "023e105f4ecef8ad9ca31a8372d0c353/../../user/tokens"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ cloudflare_zone_id is not a valid Cloudflare zone ID"
  [ ! -f "$CURL_MOCK_ARGS_FILE" ]
}

@test "Should reject a zone name that is not a hostname" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/invalid_name.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to extract domain name from Cloudflare zone response"
}

# =============================================================================
# Test: Cloudflare API call
# =============================================================================
@test "Should query the configured zone on the Cloudflare API" {
  run_cloudflare_setup

  assert_contains "$(cat "$CURL_MOCK_ARGS_FILE")" "https://api.cloudflare.com/client/v4/zones/023e105f4ecef8ad9ca31a8372d0c353"
}

@test "Should send the token through stdin and never as an argument" {
  run_cloudflare_setup

  assert_contains "$(cat "$CURL_MOCK_STDIN_FILE")" 'header = "Authorization: Bearer test-token-value"'

  if grep -q "test-token-value" "$CURL_MOCK_ARGS_FILE"; then
    echo "The API token was passed to curl as an argument"
    return 1
  fi
}

@test "Should not print the token" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  if echo "$output" | grep -q "test-token-value"; then
    echo "The API token leaked into the script output"
    return 1
  fi
}

# =============================================================================
# Test: Cloudflare API errors
# =============================================================================
@test "Should fail if the Cloudflare API is unreachable" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/success.json" 000 6

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch Cloudflare zone information"
  assert_contains "$output" "  🌐 Error: Could not reach the Cloudflare API"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Could not resolve host"
}

@test "Should fail if the token is invalid" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/invalid_token.json" 401

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to fetch Cloudflare zone information"
  assert_contains "$output" "  🔒 Error: Cloudflare rejected the API token (HTTP 401)"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The token is invalid, expired or was revoked"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    2. Ensure the token has 'Zone:Read' and 'DNS:Edit' on the zone"
}

@test "Should fail if the token is not allowed on the zone" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/forbidden.json" 403

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔒 Error: Cloudflare rejected the API token (HTTP 403)"
  assert_contains "$output" "    • The token is not allowed on zone '023e105f4ecef8ad9ca31a8372d0c353'"
}

@test "Should fail if the zone does not exist" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/not_found.json" 404

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔎 Error: Zone '023e105f4ecef8ad9ca31a8372d0c353' was not found (HTTP 404)"

  assert_contains "$output" "  💡 Possible causes:"
  assert_contains "$output" "    • The zone ID is incorrect or has a typo"
  assert_contains "$output" "    • A zone name was configured instead of the zone ID"

  assert_contains "$output" "  🔧 How to fix:"
  assert_contains "$output" "    2. Update 'network.cloudflare_zone_id' in the scope-configurations provider"
}

@test "Should treat a malformed zone ID as a zone that was not found" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/not_found.json" 400

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  🔎 Error: Zone '023e105f4ecef8ad9ca31a8372d0c353' was not found (HTTP 400)"
}

@test "Should surface the Cloudflare error on an unknown failure" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/unknown_error.json" 500

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "  📋 Error details (HTTP 500):"
  assert_contains "$output" "    10000: Unknown error getting cloudflare zone."
}

@test "Should handle a zone response without a name" {
  set_curl_mock "$CLOUDFLARE_MOCKS_DIR/zones/empty_domain.json"

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to extract domain name from Cloudflare zone response"
  assert_contains "$output" "  💡 Possible causes:"
}

# =============================================================================
# Test: Scope patch
# =============================================================================
@test "Should handle auth error updating scope domain" {
  set_np_mock "$NP_MOCKS_DIR/scope/patch/auth_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to update scope domain"
  assert_contains "$output" "  🔒 Error: Permission denied"
  assert_contains "$output" "    • The nullplatform API Key doesn't have 'Developer' permissions"
}

@test "Should handle unknown error updating scope domain" {
  set_np_mock "$NP_MOCKS_DIR/scope/patch/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "   ❌ Failed to update scope domain"
  assert_contains "$output" "  📋 Error details:"
  assert_contains "$output" "Unknown error updating scope"
}

@test "Should set the scope domain on apply" {
  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   📝 Setting scope domain to 'automation-development-tools.example.com'..."
  assert_contains "$output" "   ✅ Scope domain set successfully"
}

@test "Should not patch the scope domain on destroy" {
  export TOFU_ACTION="destroy"
  # A patch attempt would fail the script: destroy must never reach it.
  set_np_mock "$NP_MOCKS_DIR/scope/patch/unknown_error.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "   ⏭️  Not setting the scope domain: the scope's resources are being destroyed"
}

# =============================================================================
# Test: TOFU_VARIABLES - verifies the entire JSON structure
# =============================================================================
@test "Should add network variables to TOFU_VARIABLES" {
  run_cloudflare_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "network_cloudflare_zone_id": "023e105f4ecef8ad9ca31a8372d0c353",
  "network_domain": "example.com",
  "network_subdomain": "automation-development-tools",
  "network_cloudflare_proxied": false
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should pass cloudflare_proxied through as a boolean when enabled" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].network.cloudflare_proxied = true')

  run_cloudflare_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.network_cloudflare_proxied')" "true"
}

# =============================================================================
# Test: MODULES_TO_USE
# =============================================================================
@test "Should register the provider in the MODULES_TO_USE variable when it's empty" {
  run_cloudflare_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/network/cloudflare/modules"
}

@test "Should append the provider in the MODULES_TO_USE variable when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_cloudflare_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/network/cloudflare/modules"
}
