#!/bin/bash
# =============================================================================
# Azure Front Door Assertion Functions
#
# Validates the resources the front-door distribution layer creates inside a
# shared profile/endpoint, using the Azure Mock API server.
#
# Usage:
#   source "front_door_assertions.bash"
#   assert_azure_front_door_route_configured "app-name" "profile" "endpoint" "sub" "rg" "/origin/path" "full.domain" "storage" "zone" "subdomain" "rule-set-name"
# =============================================================================

_afd_profile_path() {
  echo "/subscriptions/$1/resourceGroups/$2/providers/Microsoft.Cdn/profiles/$3"
}

# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
# | Rule set exists                  | Non-empty ID                           |
# | Origin group exists              | Non-empty ID                           |
# | Origin host                      | <storage>.z13.web.core.windows.net     |
# | Route exists                     | Non-empty ID                           |
# | Route origin path                | normalized blob prefix                 |
# | Route linkToDefaultDomain        | Disabled                               |
# | Custom domain exists             | hostName = full domain                 |
# | Validation TXT record exists     | _dnsauth.<subdomain>                   |
# +----------------------------------+----------------------------------------+
assert_azure_front_door_route_configured() {
  local app_name="$1" profile="$2" endpoint="$3" subscription_id="$4" resource_group="$5"
  local origin_path="$6" full_domain="$7" storage_account="$8" zone_name="$9" subdomain="${10}" rule_set_name="${11}"

  local base
  base=$(_afd_profile_path "$subscription_id" "$resource_group" "$profile")

  local rule_set_json
  rule_set_json=$(azure_mock "${base}/ruleSets/${rule_set_name}")
  assert_not_empty "$(echo "$rule_set_json" | jq -r '.id // empty')" "Front Door rule set ID"

  local og_json
  og_json=$(azure_mock "${base}/originGroups/${app_name}-og")
  assert_not_empty "$(echo "$og_json" | jq -r '.id // empty')" "Front Door origin group ID"

  local origin_json
  origin_json=$(azure_mock "${base}/originGroups/${app_name}-og/origins/${app_name}-origin")
  assert_contains "$(echo "$origin_json" | jq -r '.properties.hostName // empty')" "$storage_account"

  local route_json
  route_json=$(azure_mock "${base}/afdEndpoints/${endpoint}/routes/${app_name}")
  assert_not_empty "$(echo "$route_json" | jq -r '.id // empty')" "Front Door route ID"
  assert_equal "$(echo "$route_json" | jq -r '.properties.originPath // empty')" "$origin_path"
  assert_equal "$(echo "$route_json" | jq -r '.properties.linkToDefaultDomain // empty')" "Disabled"

  local domain_json
  domain_json=$(azure_mock "${base}/customDomains/${app_name}-domain")
  assert_equal "$(echo "$domain_json" | jq -r '.properties.hostName // empty')" "$full_domain"

  local txt_json
  txt_json=$(azure_mock "/subscriptions/${subscription_id}/resourceGroups/${TEST_DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${zone_name}/TXT/_dnsauth.${subdomain}")
  assert_equal "$(echo "$txt_json" | jq -r '.properties.TXTRecords[0].value[0] // empty')" "mock-validation-token"
}

# Asserts every resource owned by the scope is gone: route, custom domain,
# origin group, origin, rule set and the _dnsauth validation TXT record.
assert_azure_front_door_route_not_configured() {
  local app_name="$1" profile="$2" endpoint="$3" subscription_id="$4" resource_group="$5"
  local zone_name="$6" subdomain="$7" rule_set_name="$8"
  local base
  base=$(_afd_profile_path "$subscription_id" "$resource_group" "$profile")

  assert_equal "$(azure_mock "${base}/afdEndpoints/${endpoint}/routes/${app_name}" | jq -r '.id // empty')" ""
  assert_equal "$(azure_mock "${base}/originGroups/${app_name}-og" | jq -r '.id // empty')" ""
  assert_equal "$(azure_mock "${base}/originGroups/${app_name}-og/origins/${app_name}-origin" | jq -r '.id // empty')" ""
  assert_equal "$(azure_mock "${base}/customDomains/${app_name}-domain" | jq -r '.id // empty')" ""
  assert_equal "$(azure_mock "${base}/ruleSets/${rule_set_name}" | jq -r '.id // empty')" ""

  local txt_path="/subscriptions/${subscription_id}/resourceGroups/${TEST_DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnszones/${zone_name}/TXT/_dnsauth.${subdomain}"
  assert_equal "$(azure_mock "$txt_path" | jq -r '.id // empty')" ""
}

assert_azure_front_door_shared_resources_exist() {
  local profile="$1" endpoint="$2" subscription_id="$3" resource_group="$4"
  local base
  base=$(_afd_profile_path "$subscription_id" "$resource_group" "$profile")

  assert_not_empty "$(azure_mock "$base" | jq -r '.id // empty')" "Shared Front Door profile ID"
  assert_not_empty "$(azure_mock "${base}/afdEndpoints/${endpoint}" | jq -r '.id // empty')" "Shared Front Door endpoint ID"
}

assert_azure_front_door_purged() {
  local full_domain="$1"
  local purges
  purges=$(azure_mock "/mock/afd/purges")
  local matching
  matching=$(echo "$purges" | jq --arg d "$full_domain" '[.[] | select(.domains | index($d))] | length')
  assert_equal "$matching" "1"
}
