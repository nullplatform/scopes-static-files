#!/usr/bin/env bats
# =============================================================================
# Integration test: Azure Front Door + Azure DNS Lifecycle
#
#   1. Seed the customer-owned prerequisites (profile, endpoint, zone, storage)
#   2. Create infrastructure (route + custom domain + TXT + CNAME + purge)
#   3. Destroy infrastructure
#   4. Verify the scope's resources are gone and the shared ones remain
# =============================================================================

TEST_DISTRIBUTION_STORAGE_ACCOUNT="assetsaccount"
TEST_DISTRIBUTION_ORIGIN_PATH="/tools/automation/v1.0.0"
TEST_DISTRIBUTION_APP_NAME="automation-development-tools-7"
TEST_FRONT_DOOR_PROFILE="shared-afd"
TEST_FRONT_DOOR_ENDPOINT="shared-endpoint"

TEST_NETWORK_DOMAIN="frontend.publicdomain.com"
TEST_NETWORK_SUBDOMAIN="automation-development-tools"
TEST_NETWORK_FULL_DOMAIN="automation-development-tools.frontend.publicdomain.com"

TEST_SUBSCRIPTION_ID="mock-subscription-id"
TEST_RESOURCE_GROUP="test-resource-group"
TEST_DNS_ZONE_RESOURCE_GROUP="dns-resource-group"

setup_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  integration_setup --cloud-provider azure
  clear_mocks

  export TEST_SUBSCRIPTION_ID TEST_RESOURCE_GROUP TEST_DNS_ZONE_RESOURCE_GROUP
}

teardown_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  clear_mocks
  integration_teardown
}

seed_shared_resources() {
  local base="/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_RESOURCE_GROUP}/providers"

  azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${TEST_NETWORK_DOMAIN}" '{"location": "global", "tags": {}}' >/dev/null
  azure_mock_put "${base}/Microsoft.Storage/storageAccounts/${TEST_DISTRIBUTION_STORAGE_ACCOUNT}" \
    '{"location": "eastus", "kind": "StorageV2", "sku": {"name": "Standard_LRS", "tier": "Standard"}}' >/dev/null
  azure_mock_put "${base}/Microsoft.Cdn/profiles/${TEST_FRONT_DOOR_PROFILE}" \
    '{"location": "global", "sku": {"name": "Standard_AzureFrontDoor"}}' >/dev/null
  azure_mock_put "${base}/Microsoft.Cdn/profiles/${TEST_FRONT_DOOR_PROFILE}/afdEndpoints/${TEST_FRONT_DOOR_ENDPOINT}" \
    '{"location": "global", "properties": {"enabledState": "Enabled"}}' >/dev/null
}

setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  source "${PROJECT_ROOT}/testing/assertions.sh"
  source "${BATS_TEST_DIRNAME}/front_door_assertions.bash"
  source "${BATS_TEST_DIRNAME}/dns_assertions.bash"

  clear_mocks
  curl -s -X DELETE "${AZURE_MOCK_ENDPOINT}/mock/afd/purges" >/dev/null
  load_context "static-files/deployment/tests/resources/context_azure.json"

  export NETWORK_LAYER="azure_dns"
  export DISTRIBUTION_LAYER="front-door"
  export TOFU_PROVIDER="azure"
  export SERVICE_PATH="$INTEGRATION_MODULE_ROOT/static-files"
  export CUSTOM_TOFU_MODULES="$INTEGRATION_MODULE_ROOT/testing/azure-mock-provider"

  export AZURE_SUBSCRIPTION_ID="$TEST_SUBSCRIPTION_ID"
  export AZURE_RESOURCE_GROUP="$TEST_RESOURCE_GROUP"
  export TOFU_PROVIDER_STORAGE_ACCOUNT="devstoreaccount1"
  export TOFU_PROVIDER_CONTAINER="tfstate"
  export AZURE_FRONT_DOOR_PROFILE="$TEST_FRONT_DOOR_PROFILE"
  export AZURE_FRONT_DOOR_ENDPOINT="$TEST_FRONT_DOOR_ENDPOINT"

  local mocks_dir="static-files/deployment/tests/integration/mocks/"
  mock_request "PATCH" "/scope/7" "$mocks_dir/scope/patch.json"

  curl -s -X PUT "${AZURE_MOCK_ENDPOINT}/tfstate?restype=container" \
    -H "Host: devstoreaccount1.blob.core.windows.net" \
    -H "x-ms-version: 2021-06-08" >/dev/null 2>&1 || true

  seed_shared_resources
}

@test "create infrastructure adds a route, custom domain and DNS records to the shared endpoint" {
  run_workflow "static-files/deployment/workflows/initial.yaml"

  assert_azure_front_door_route_configured \
    "$TEST_DISTRIBUTION_APP_NAME" "$TEST_FRONT_DOOR_PROFILE" "$TEST_FRONT_DOOR_ENDPOINT" \
    "$TEST_SUBSCRIPTION_ID" "$TEST_RESOURCE_GROUP" \
    "$TEST_DISTRIBUTION_ORIGIN_PATH" "$TEST_NETWORK_FULL_DOMAIN" \
    "$TEST_DISTRIBUTION_STORAGE_ACCOUNT" "$TEST_NETWORK_DOMAIN" "$TEST_NETWORK_SUBDOMAIN"

  assert_azure_dns_configured \
    "$TEST_NETWORK_SUBDOMAIN" "$TEST_NETWORK_DOMAIN" \
    "$TEST_SUBSCRIPTION_ID" "$TEST_DNS_ZONE_RESOURCE_GROUP"

  assert_azure_front_door_purged "$TEST_NETWORK_FULL_DOMAIN"
}

@test "destroy infrastructure keeps the shared profile and endpoint" {
  run_workflow "static-files/deployment/workflows/delete.yaml"

  assert_azure_front_door_route_not_configured \
    "$TEST_DISTRIBUTION_APP_NAME" "$TEST_FRONT_DOOR_PROFILE" "$TEST_FRONT_DOOR_ENDPOINT" \
    "$TEST_SUBSCRIPTION_ID" "$TEST_RESOURCE_GROUP"

  assert_azure_dns_not_configured \
    "$TEST_NETWORK_SUBDOMAIN" "$TEST_NETWORK_DOMAIN" \
    "$TEST_SUBSCRIPTION_ID" "$TEST_DNS_ZONE_RESOURCE_GROUP"

  assert_azure_front_door_shared_resources_exist \
    "$TEST_FRONT_DOOR_PROFILE" "$TEST_FRONT_DOOR_ENDPOINT" \
    "$TEST_SUBSCRIPTION_ID" "$TEST_RESOURCE_GROUP"
}
