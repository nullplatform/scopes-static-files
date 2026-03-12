#!/bin/bash
# =============================================================================
# Azure Static Web Apps Assertion Functions
#
# Provides assertion functions for validating Azure Static Web Apps
# configuration in integration tests using the Azure Mock API server.
#
# Variables validated (from distribution/static-web-apps/modules/variables.tf):
#   - distribution_app_name         -> Static Web App name
#
# Usage:
#   source "swa_assertions.bash"
#   assert_azure_swa_configured "app-name" "sub-id" "rg"
#
# Note: Uses azure_mock() helper from integration_helpers.sh
# =============================================================================

# =============================================================================
# Azure Static Web App Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Static Web App exists            | Non-empty ID                           |
# | Provisioning state               | Succeeded                              |
# | Default hostname                 | Contains azurestaticapps.net           |
# +----------------------------------+----------------------------------------+
assert_azure_swa_configured() {
	local app_name="$1"
	local subscription_id="$2"
	local resource_group="$3"

	# Get Static Web App
	local swa_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/staticSites/${app_name}"
	local swa_json
	swa_json=$(azure_mock "$swa_path")

	# Static Web App exists
	local swa_id
	swa_id=$(echo "$swa_json" | jq -r '.id // empty')
	assert_not_empty "$swa_id" "Azure Static Web App ID"

	# Provisioning state
	local swa_state
	swa_state=$(echo "$swa_json" | jq -r '.properties.provisioningState // empty')
	assert_equal "$swa_state" "Succeeded"

	# Default hostname contains azurestaticapps.net
	local hostname
	hostname=$(echo "$swa_json" | jq -r '.properties.defaultHostname // empty')
	assert_not_empty "$hostname" "Azure Static Web App default hostname"
	assert_contains "$hostname" "azurestaticapps.net"
}

# =============================================================================
# Azure Static Web App Not Configured Assertion
# =============================================================================
# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Static Web App exists            | null/empty (deleted)                   |
# +----------------------------------+----------------------------------------+
assert_azure_swa_not_configured() {
	local app_name="$1"
	local subscription_id="$2"
	local resource_group="$3"

	# Check Static Web App is deleted
	local swa_path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/staticSites/${app_name}"
	local swa_json
	swa_json=$(azure_mock "$swa_path")

	local swa_error
	swa_error=$(echo "$swa_json" | jq -r '.error.code // empty')
	if [[ "$swa_error" != "ResourceNotFound" ]]; then
		local swa_id
		swa_id=$(echo "$swa_json" | jq -r '.id // empty')
		if [[ -n "$swa_id" && "$swa_id" != "null" ]]; then
			echo "Expected Azure Static Web App to be deleted"
			echo "Actual: '$swa_json'"
			return 1
		fi
	fi

	return 0
}
