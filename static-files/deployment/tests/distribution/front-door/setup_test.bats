#!/usr/bin/env bats
# =============================================================================
# Unit tests for distribution/front-door/setup script
#
# Run tests:
#   bats tests/distribution/front-door/setup_test.bats
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
  PROJECT_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
  SCRIPT_PATH="$PROJECT_DIR/distribution/front-door/setup"
  RESOURCES_DIR="$PROJECT_DIR/tests/resources"
  AZURE_MOCKS_DIR="$RESOURCES_DIR/azure_mocks"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export PATH="$AZURE_MOCKS_DIR:$PATH"
  set_az_mock "$AZURE_MOCKS_DIR/afd_endpoint/success.json" 0

  export CONTEXT='{
    "application": {"slug": "automation"},
    "scope": {"slug": "development-tools", "id": "7", "nrn": "organization=1:account=2:namespace=3:application=4:scope=7"},
    "asset": {"url": "https://mystaticstorage.blob.core.windows.net/%24web/tools/automation/v1.0.0"},
    "providers": {
      "scope-configurations": {
        "provider": {
          "azure_subscription_id": "00000000-0000-0000-0000-000000000000",
          "azure_resource_group": "my-resource-group"
        },
        "distribution": {
          "azure_front_door_profile": "shared-afd",
          "azure_front_door_endpoint": "shared-endpoint"
        }
      }
    }
  }'

  export TOFU_VARIABLES='{
    "application_slug": "automation",
    "scope_slug": "development-tools",
    "scope_id": "7"
  }'

  export MODULES_TO_USE=""
}

run_front_door_setup() {
  source "$SCRIPT_PATH"
}

@test "Should extract storage account, container and prefix from asset URL" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_storage_account')" "mystaticstorage"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')" '$web'
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')" "/tools/automation/v1.0.0"
}

@test "Should decode a URL-encoded \$web container" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/%24web/frontends/4/612605537"')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')" '$web'
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')" "/frontends/4/612605537"
}

@test "Should fail when the container is not \$web" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/assets/tools/automation/v1.0.0"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Container 'assets' cannot be served by Front Door: the static-website origin only serves the \$web container"
  assert_contains "$output" "🔧 How to fix:"
}

@test "Should use root prefix when asset URL has no path after container" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/%24web"')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')" "/"
}

@test "Should fail when asset URL is not Azure Blob Storage format" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "s3://bucket/path"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Could not extract storage account from asset URL"
  assert_contains "$output" "🔧 How to fix:"
}

@test "Should read the Front Door profile and endpoint from the scope configuration" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_front_door_profile')" "shared-afd"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_front_door_endpoint')" "shared-endpoint"
}

@test "Should default the Front Door resource group to the provider resource group" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_front_door_resource_group')" "my-resource-group"
}

@test "Should prefer an explicit Front Door resource group" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_resource_group = "cdn-rg"')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_front_door_resource_group')" "cdn-rg"
}

@test "Should fall back to environment variables for profile and endpoint" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].distribution)')
  export AZURE_FRONT_DOOR_PROFILE="env-profile"
  export AZURE_FRONT_DOOR_ENDPOINT="env-endpoint"

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_front_door_profile')" "env-profile"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_front_door_endpoint')" "env-endpoint"
}

@test "Should fail when the Front Door profile is not configured" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].distribution.azure_front_door_profile)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_front_door_profile is missing"
  assert_contains "$output" "distribution.azure_front_door_profile"
}

@test "Should fail when the Front Door endpoint is not configured" {
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.providers["scope-configurations"].distribution.azure_front_door_endpoint)')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_front_door_endpoint is missing"
}

@test "Should fail with guidance when the shared endpoint does not exist" {
  set_az_mock "$AZURE_MOCKS_DIR/afd_endpoint/not_found.json" 1

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Front Door endpoint 'shared-endpoint' was not found in profile 'shared-afd'"
  assert_contains "$output" "az afd endpoint create"
}

@test "Should default the cached path prefixes to /static/" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_cached_path_prefixes')" '["/static/"]'
}

@test "Should default the cached path prefixes when the list is empty" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cached_path_prefixes = []')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_cached_path_prefixes')" '["/static/"]'
}

@test "Should read explicit cached path prefixes and drop empty entries" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cached_path_prefixes = ["/assets/", "", "/fonts/"]')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_cached_path_prefixes')" '["/assets/","/fonts/"]'
}

@test "Should fail when a cached path prefix does not start with a slash" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cached_path_prefixes = ["/assets/", "fonts/"]')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ Cached path prefix 'fonts/' must start with '/'"
  assert_contains "$output" "distribution.azure_front_door_cached_path_prefixes"
  assert_contains "$output" "🔧 How to fix:"
}

@test "Should fail when more than 10 cached path prefixes are configured" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cached_path_prefixes = ["/a/","/b/","/c/","/d/","/e/","/f/","/g/","/h/","/i/","/j/","/k/"]')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ At most 10 cached path prefixes are allowed, got 11"
}

@test "Should default the cache duration to 7 days" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_cache_days')" "7"
}

@test "Should read an explicit cache duration as a number" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cache_days = 30')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_cache_days')" "30"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_cache_days | type')" "number"
}

@test "Should fail when the cache duration is below 1 day" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cache_days = 0')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_front_door_cache_days must be an integer between 1 and 365, got '0'"
  assert_contains "$output" "🔧 How to fix:"
}

@test "Should fail when the cache duration is above 365 days" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cache_days = 366')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_front_door_cache_days must be an integer between 1 and 365, got '366'"
}

@test "Should fail when the cache duration is not an integer" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_cache_days = 1.5')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_front_door_cache_days must be an integer between 1 and 365, got '1.5'"
}

@test "Should leave the security headers off by default" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_security_headers')" "false"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_content_security_policy')" '""'
}

@test "Should enable the security headers with a content security policy" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_security_headers = true
    | .providers["scope-configurations"].distribution.azure_front_door_content_security_policy = "default-src '"'"'self'"'"'"')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_security_headers')" "true"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_content_security_policy')" "default-src 'self'"
}

@test "Should enable the security headers without a content security policy" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_security_headers = true')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_security_headers')" "true"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_content_security_policy')" '""'
}

@test "Should warn and ignore a content security policy while the security headers are off" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_content_security_policy = "default-src '"'"'self'"'"'"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "⚠️  azure_front_door_content_security_policy is ignored: azure_front_door_security_headers is off"

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_security_headers')" "false"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_content_security_policy')" '""'
}

@test "Should default the certificate secret to empty (managed certificate)" {
  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_certificate_secret')" '""'
}

@test "Should read the certificate secret from the scope configuration" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_certificate_secret = "wildcard-np-example-com"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "0"
  assert_contains "$output" "✅ certificate_secret=wildcard-np-example-com"

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_certificate_secret')" "wildcard-np-example-com"
}

@test "Should fall back to AZURE_FRONT_DOOR_CERTIFICATE_SECRET for the certificate secret" {
  export AZURE_FRONT_DOOR_CERTIFICATE_SECRET="env-certificate"

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_certificate_secret')" "env-certificate"
}

@test "Should fail when the certificate secret name is invalid" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.azure_front_door_certificate_secret = "my_certificate"')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "❌ azure_front_door_certificate_secret 'my_certificate' is not a valid Front Door secret name"
  assert_contains "$output" "🔧 How to fix:"
}

@test "Should fail when the certificate secret name is longer than 260 characters" {
  local long_name
  long_name=$(printf 'a%.0s' {1..261})
  export CONTEXT=$(echo "$CONTEXT" | jq --arg name "$long_name" '.providers["scope-configurations"].distribution.azure_front_door_certificate_secret = $name')

  run source "$SCRIPT_PATH"

  assert_equal "$status" "1"
  assert_contains "$output" "is not a valid Front Door secret name"
}

@test "Should add distribution variables to TOFU_VARIABLES" {
  run_front_door_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_storage_account": "mystaticstorage",
  "distribution_container_name": "$web",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_blob_prefix": "/tools/automation/v1.0.0",
  "distribution_resource_tags_json": {},
  "distribution_front_door_profile": "shared-afd",
  "distribution_front_door_endpoint": "shared-endpoint",
  "distribution_front_door_resource_group": "my-resource-group",
  "distribution_cached_path_prefixes": ["/static/"],
  "distribution_cache_days": 7,
  "distribution_security_headers": false,
  "distribution_content_security_policy": "",
  "distribution_certificate_secret": ""
}'

  assert_json_equal "$TOFU_VARIABLES" "$expected" "TOFU_VARIABLES"
}

@test "Should register the module in MODULES_TO_USE when it's empty" {
  run_front_door_setup

  assert_equal "$MODULES_TO_USE" "$PROJECT_DIR/distribution/front-door/modules"
}

@test "Should append the module to MODULES_TO_USE when it's not empty" {
  export MODULES_TO_USE="existing/module"

  run_front_door_setup

  assert_equal "$MODULES_TO_USE" "existing/module,$PROJECT_DIR/distribution/front-door/modules"
}

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

# az stub that answers by URL: the scope's origin from ORIGIN_RESPONSE (exit
# ORIGIN_EXIT), anything else (the endpoint preflight) with the success mock.
use_origin_aware_az() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/az" <<STUB
#!/bin/bash
if [[ "\$*" == */origins/* ]]; then
  if [ "\${ORIGIN_EXIT:-0}" -eq 0 ]; then cat "\$ORIGIN_RESPONSE"; else cat "\$ORIGIN_RESPONSE" >&2; fi
  exit "\${ORIGIN_EXIT:-0}"
fi
cat "$AZURE_MOCKS_DIR/afd_endpoint/success.json"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/az"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "Should take the storage account from the existing origin when deleting a scope without the attribute" {
  export STATIC_FILES_PHASE="scope-delete"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.asset)')
  echo '{"properties": {"hostName": "legacystorage.z13.web.core.windows.net"}}' > "$BATS_TEST_TMPDIR/origin.json"
  export ORIGIN_RESPONSE="$BATS_TEST_TMPDIR/origin.json"
  use_origin_aware_az

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_storage_account')" "legacystorage"
  assert_equal "${TOFU_ACTION:-}" ""
}

@test "Should skip deleting a scope without the attribute when its origin does not exist" {
  export STATIC_FILES_PHASE="scope-delete"
  export TOFU_ACTION="destroy"
  export CONTEXT=$(echo "$CONTEXT" | jq 'del(.asset)')
  export ORIGIN_RESPONSE="$AZURE_MOCKS_DIR/afd_endpoint/not_found.json"
  export ORIGIN_EXIT=1
  use_origin_aware_az

  run_front_door_setup

  assert_equal "$TOFU_ACTION" "skip"
}
