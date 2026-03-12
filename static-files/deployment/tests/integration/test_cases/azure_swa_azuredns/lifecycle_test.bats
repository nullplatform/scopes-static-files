#!/usr/bin/env bats
# =============================================================================
# Integration test: Azure Static Web Apps + Azure DNS Lifecycle
#
# Tests the full lifecycle of a static files deployment on Azure:
#   1. Create infrastructure (Static Web App + DNS CNAME record)
#   2. Verify all resources are configured correctly
#   3. Destroy infrastructure
#   4. Verify all resources are removed
# =============================================================================

# =============================================================================
# Test Constants
# =============================================================================
# Expected values derived from context_azure.json and terraform variables

# SWA variables (distribution/static-web-apps/modules/variables.tf)
TEST_DISTRIBUTION_APP_NAME="automation-development-tools-7"                    # distribution_app_name

# DNS variables (network/azure_dns/modules/variables.tf)
TEST_NETWORK_DOMAIN="frontend.publicdomain.com"                                # network_domain
TEST_NETWORK_SUBDOMAIN="automation-development-tools"                          # network_subdomain
TEST_NETWORK_FULL_DOMAIN="automation-development-tools.frontend.publicdomain.com"  # computed

# Azure resource identifiers
TEST_SUBSCRIPTION_ID="mock-subscription-id"
TEST_RESOURCE_GROUP="test-resource-group"
TEST_DNS_ZONE_RESOURCE_GROUP="dns-resource-group"

# =============================================================================
# Test Setup
# =============================================================================

setup_file() {
	source "${PROJECT_ROOT}/testing/integration_helpers.sh"
	source "${PROJECT_ROOT}/testing/assertions.sh"
	integration_setup --cloud-provider azure

	clear_mocks

	# Pre-create Azure DNS zone in the mock server (required for data source lookup)
	echo "Creating test prerequisites in Azure Mock..."

	# Create DNS zone in dns-resource-group (for validation step in setup_network_layer)
	azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${TEST_NETWORK_DOMAIN}" \
		'{"location": "global", "tags": {}}' >/dev/null 2>&1 || true

	# Also create DNS zone in test-resource-group (for Terraform data source lookup)
	# The azure_dns module uses var.azure_provider.resource_group which is test-resource-group
	azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${TEST_NETWORK_DOMAIN}" \
		'{"location": "global", "tags": {}}' >/dev/null 2>&1 || true

	export TEST_SUBSCRIPTION_ID
	export TEST_RESOURCE_GROUP
	export TEST_DNS_ZONE_RESOURCE_GROUP
}

teardown_file() {
	source "${PROJECT_ROOT}/testing/integration_helpers.sh"
	clear_mocks
	integration_teardown
}

setup() {
	source "${PROJECT_ROOT}/testing/integration_helpers.sh"
	source "${PROJECT_ROOT}/testing/assertions.sh"
	source "${BATS_TEST_DIRNAME}/swa_assertions.bash"
	source "${BATS_TEST_DIRNAME}/dns_assertions.bash"

	clear_mocks
	load_context "static-files/deployment/tests/resources/context_azure.json"

	# Export environment variables
	export NETWORK_LAYER="azure_dns"
	export DISTRIBUTION_LAYER="static-web-apps"
	export TOFU_PROVIDER="azure"
	export SERVICE_PATH="$INTEGRATION_MODULE_ROOT/static-files"
	export CUSTOM_TOFU_MODULES="$INTEGRATION_MODULE_ROOT/testing/azure-mock-provider"

	# Azure provider required environment variables
	export AZURE_SUBSCRIPTION_ID="$TEST_SUBSCRIPTION_ID"
	export AZURE_RESOURCE_GROUP="$TEST_RESOURCE_GROUP"
	# Use mock storage account for backend (handled by azure-mock)
	export TOFU_PROVIDER_STORAGE_ACCOUNT="devstoreaccount1"
	export TOFU_PROVIDER_CONTAINER="tfstate"

	# Setup API mocks for np CLI calls
	local mocks_dir="static-files/deployment/tests/integration/mocks/"
	mock_request "PATCH" "/scope/7" "$mocks_dir/scope/patch.json"

	# Create a temporary artifact directory with an index.html file for the SWA deployment
	# ARTIFACT_DIR is checked by the setup script — if set, it skips the blob download
	export ARTIFACT_DIR="$(mktemp -d)"
	echo '<!DOCTYPE html><html><body><h1>Test</h1></body></html>' > "${ARTIFACT_DIR}/index.html"

	# Ensure tfstate container exists in azure-mock for Terraform backend
	curl -s -X PUT "${AZURE_MOCK_ENDPOINT}/tfstate?restype=container" \
		-H "Host: devstoreaccount1.blob.core.windows.net" \
		-H "x-ms-version: 2021-06-08" >/dev/null 2>&1 || true

	# Ensure DNS zone exists in azure-mock (for validation and Terraform data source)
	azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${TEST_NETWORK_DOMAIN}" \
		'{"location": "global", "tags": {}}' >/dev/null 2>&1 || true
	azure_mock_put "/subscriptions/${TEST_SUBSCRIPTION_ID}/resourceGroups/${TEST_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${TEST_NETWORK_DOMAIN}" \
		'{"location": "global", "tags": {}}' >/dev/null 2>&1 || true
}

# =============================================================================
# Test: Create Infrastructure
# =============================================================================

@test "create infrastructure deploys Azure Static Web App and DNS resources" {
	run_workflow "static-files/deployment/workflows/initial.yaml"

	assert_azure_swa_configured \
		"$TEST_DISTRIBUTION_APP_NAME" \
		"$TEST_SUBSCRIPTION_ID" \
		"$TEST_RESOURCE_GROUP"

	assert_azure_dns_configured \
		"$TEST_NETWORK_SUBDOMAIN" \
		"$TEST_NETWORK_DOMAIN" \
		"$TEST_SUBSCRIPTION_ID" \
		"$TEST_RESOURCE_GROUP"
}

# =============================================================================
# Test: Destroy Infrastructure
# =============================================================================

@test "destroy infrastructure removes Azure Static Web App and DNS resources" {
	run_workflow "static-files/deployment/workflows/delete.yaml"

	assert_azure_swa_not_configured \
		"$TEST_DISTRIBUTION_APP_NAME" \
		"$TEST_SUBSCRIPTION_ID" \
		"$TEST_RESOURCE_GROUP"

	assert_azure_dns_not_configured \
		"$TEST_NETWORK_SUBDOMAIN" \
		"$TEST_NETWORK_DOMAIN" \
		"$TEST_SUBSCRIPTION_ID" \
		"$TEST_DNS_ZONE_RESOURCE_GROUP"
}
