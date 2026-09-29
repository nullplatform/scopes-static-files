# Azure Front Door Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve static-files scopes on Azure through a customer-owned Front Door profile and endpoint, one route and one custom domain per scope, and remove the retired Azure CDN classic (`blob-cdn`) layer.

**Architecture:** A new `distribution/front-door` layer reads the shared profile and endpoint through data sources and creates the scope's origin group, origin, rule set, route, custom domain, validation TXT record and domain association. `network/azure_dns` keeps its contract (a CNAME to whatever `distribution_target_domain` says) and gains the resource-group fix it needs for the TXT record. The Azure mock in the `testing/` submodule learns the AFD resources so the integration suite covers the new layer; `blob-cdn` and everything that references it is deleted.

**Tech Stack:** OpenTofu (`azurerm >= 3.117, < 4.0`), bash + jq, BATS, `tofu test` (`.tftest.hcl`), Go (Azure mock in `nullplatform/scope-testing`), JSON Schema + JSONForms uiSchema, Docker (worker image).

**Spec:** `docs/design/azure-front-door.md`

## Global Constraints

- Provider constraint is `azurerm >= 3.117, < 4.0`, written identically in `provider/azure/modules/provider.tf` and in every `test_versions.tf`. Rule blocks use the 3.x names (`url_rewrite_action`, `url_file_extension_condition`, `url_path_condition`, `route_configuration_override_action`).
- The route is never linked to the endpoint's default domain: `link_to_default_domain = false`, always.
- A custom domain is mandatory. The module refuses to plan when `local.network_full_domain == ""`.
- The scope creates nothing at profile or endpoint level. Profile and endpoint are `data` sources only.
- Purge is `POST .../afdEndpoints/<endpoint>/purge?api-version=2025-04-15` with body `{"contentPaths":["/*"],"domains":["<network_full_domain>"]}`, executed with `az rest`, triggered by a change of `local.distribution_origin_path`.
- Every variable the layer adds to `TOFU_VARIABLES` carries the `distribution_` prefix; the network layer's new one carries `network_`.
- Rule set and rule names contain only letters and digits and start with a letter (Azure rejects hyphens there). Every other AFD resource name is `<app>-<scope>-<id>` plus a suffix.
- No `Co-Authored-By` trailers in commits. Conventional commit prefixes.
- Mock changes go to the `testing/` submodule (repo `nullplatform/scope-testing`) on their own branch and PR; this repo then bumps the submodule pointer.
- Never delete `blob-cdn` before Task 5's module tests pass: the schema consistency test in `tests/specs/layer_selection_test.bats` fails if the enum names a directory that does not exist.

## Review Focus

1. **Asset URL with a URL-encoded container** (`https://acct.blob.core.windows.net/%24web/frontends/1/2`): the setup must yield container `$web` and prefix `/frontends/1/2`. Pinned in Task 3 (`Should decode a URL-encoded $web container`).
2. **Scope without a network layer** (`network_full_domain` empty): planning must fail with a message naming the DNS zone requirement, never produce a route without a domain. Pinned in Task 5 (`fails_without_custom_domain`).
3. **App and scope slugs that break Azure naming** (hyphens, a 70-character `<app>-<scope>-<id>`): rule set and rule names must be sanitized and truncated to 60 characters. Pinned in Task 5 (`rule_set_name_is_alphanumeric_and_short`).
4. **Deleting a scope must not touch the shared endpoint or profile**: after `delete.yaml` both still exist in the mock. Pinned in Task 9 (`destroy infrastructure keeps the shared profile and endpoint`).
5. **Purge issued before the managed certificate is validated**: on a brand-new scope the domain is `Pending` when the first purge runs. Whether Azure accepts a purge scoped to a pending domain cannot be pinned in a mock; it is the first item of the real end-to-end checklist in Task 10.

---

### Task 1: Pin azurerm and ship `az` in the worker image

**Files:**
- Modify: `static-files/deployment/provider/azure/modules/provider.tf:8-12`
- Modify: `static-files/deployment/tofu_state/azure/modules/provider.tf:5-9`
- Modify: `Dockerfile:9-11`
- Test: `static-files/deployment/tests/provider/azure/setup_test.bats` (existing, must keep passing)

**Interfaces:**
- Produces: the version constraint string `">= 3.117, < 4.0"` reused verbatim by every `test_versions.tf` in later tasks; the `az` binary on `PATH` inside the worker image.

- [ ] **Step 1: Tighten the provider constraint**

In `static-files/deployment/provider/azure/modules/provider.tf` replace the `required_providers` block:

```hcl
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.117, < 4.0"
    }
  }
```

Apply the same replacement in `static-files/deployment/tofu_state/azure/modules/provider.tf`.

- [ ] **Step 2: Verify the constraint resolves**

Run:
```bash
cd static-files/deployment/provider/azure/modules && rm -rf .terraform .terraform.lock.hcl && tofu init -backend=false -input=false | grep -i "azurerm"
```
Expected: `Installing hashicorp/azurerm v3.117.x`.

- [ ] **Step 3: Add azure-cli to the worker image**

In `Dockerfile` replace the tooling block (lines 9-11) with:

```dockerfile
# Tooling the static-files workflows call: aws + gomplate from apk, az from pip
# (Alpine has no azure-cli package). az is needed by network/azure_dns/setup
# and by the Front Door purge in distribution/front-door.
RUN apk add --no-cache aws-cli gomplate py3-pip \
    && pip3 install --no-cache-dir --break-system-packages azure-cli \
    && az version
```

- [ ] **Step 4: Build the image**

Run: `docker build -t scopes-static-files-worker:dev .`
Expected: build succeeds and the `az version` layer prints a JSON with `"azure-cli"`.

- [ ] **Step 5: Run the existing provider tests**

Run: `bats static-files/deployment/tests/provider/azure/setup_test.bats`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Dockerfile static-files/deployment/provider/azure/modules/provider.tf static-files/deployment/tofu_state/azure/modules/provider.tf
git commit -m "chore(azure): pin azurerm to 3.117+ and ship azure-cli in the worker image"
```

---

### Task 2: Forward the DNS zone resource group through `network/azure_dns`

**Files:**
- Modify: `static-files/deployment/network/azure_dns/setup:130-140`
- Modify: `static-files/deployment/network/azure_dns/modules/variables.tf`
- Modify: `static-files/deployment/network/azure_dns/modules/main.tf`
- Create: `static-files/deployment/network/azure_dns/modules/test_versions.tf`
- Modify: `static-files/deployment/network/azure_dns/modules/azure_dns.tftest.hcl`
- Test: `static-files/deployment/tests/network/azure_dns/setup_test.bats`

**Interfaces:**
- Produces: `TOFU_VARIABLES.network_dns_zone_resource_group` (string) and `var.network_dns_zone_resource_group` in the composed root module. Task 5 reads this variable for the TXT record and the zone data source.

- [ ] **Step 1: Write the failing BATS test**

Append to `static-files/deployment/tests/network/azure_dns/setup_test.bats`:

```bash
# =============================================================================
# Test: DNS zone resource group is forwarded to tofu
# =============================================================================
@test "Should add network_dns_zone_resource_group to TOFU_VARIABLES" {
  set_az_mock "$AZURE_MOCKS_DIR/dns_zone/success.json" 0

  source "$SCRIPT_PATH"

  local rg=$(echo "$TOFU_VARIABLES" | jq -r '.network_dns_zone_resource_group')
  assert_equal "$rg" "my-resource-group"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats static-files/deployment/tests/network/azure_dns/setup_test.bats -f "network_dns_zone_resource_group"`
Expected: FAIL, `expected "my-resource-group", got "null"`.

- [ ] **Step 3: Forward the value in the setup script**

In `static-files/deployment/network/azure_dns/setup`, replace the `TOFU_VARIABLES=$(...)` block with:

```bash
TOFU_VARIABLES=$(echo "$TOFU_VARIABLES" | jq \
  --arg dns_zone_name "$public_dns_zone_name" \
  --arg dns_zone_resource_group "$public_dns_zone_resource_group_name" \
  --arg domain "$network_domain" \
  --arg subdomain "$network_subdomain" \
  '. + {
    network_dns_zone_name: $dns_zone_name,
    network_dns_zone_resource_group: $dns_zone_resource_group,
    network_domain: $domain,
    network_subdomain: $subdomain
  }')
```

- [ ] **Step 4: Run the BATS file**

First update the existing full-JSON test `Should add network variables to TOFU_VARIABLES` (line 264): add the line `"network_dns_zone_resource_group": "my-resource-group",` to its `expected` object, right after `"network_dns_zone_name": "example.com",`.

Run: `bats static-files/deployment/tests/network/azure_dns/setup_test.bats`
Expected: 14 tests PASS.

- [ ] **Step 5: Declare the variable and use it in the module**

Append to `static-files/deployment/network/azure_dns/modules/variables.tf`:

```hcl
variable "network_dns_zone_resource_group" {
  description = "Resource group that holds the Azure DNS zone (may differ from the scope's resource group)"
  type        = string
}
```

In `static-files/deployment/network/azure_dns/modules/main.tf` replace every `resource_group_name = var.azure_provider.resource_group` (three occurrences: the data source, the CNAME record, the A record) with:

```hcl
  resource_group_name = var.network_dns_zone_resource_group
```

- [ ] **Step 6: Pin the provider for isolated tests**

Create `static-files/deployment/network/azure_dns/modules/test_versions.tf`:

```hcl
# =============================================================================
# Test-only provider pin
#
# compose_modules skips test_*.tf, so this never reaches a composed root
# module (provider/azure/modules/provider.tf owns the constraint there).
# `tofu test` on this directory alone would otherwise resolve the newest
# azurerm, whose 4.x/5.x schemas differ from the 3.x one the modules target.
# =============================================================================
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.117, < 4.0"
    }
  }
}
```

- [ ] **Step 7: Add the tftest assertion and update the variables block**

In `static-files/deployment/network/azure_dns/modules/azure_dns.tftest.hcl`, add to the top-level `variables { ... }` block:

```hcl
  network_dns_zone_resource_group = "dns-resource-group"
```

Append a run block:

```hcl
# =============================================================================
# Test: Records go to the zone's resource group, not the scope's
# =============================================================================
run "records_use_dns_zone_resource_group" {
  command = plan

  assert {
    condition     = azurerm_dns_cname_record.main[0].resource_group_name == "dns-resource-group"
    error_message = "CNAME record should be created in the DNS zone resource group"
  }
}
```

- [ ] **Step 8: Run the tofu tests**

Run:
```bash
cd static-files/deployment/network/azure_dns/modules && rm -rf .terraform .terraform.lock.hcl && tofu init -backend=false -input=false >/dev/null && tofu test
```
Expected: all runs PASS, including `records_use_dns_zone_resource_group`.

- [ ] **Step 9: Update the install example comment**

In `static-files/specs/install/azure/main.tf`, replace the comment block above `azure_dns_zone_resource_group` (the one starting `# Must equal the scope's resource group`) with:

```hcl
      # Resource group that holds the DNS zone. It may differ from the scope's
      # resource group: the setup validates the zone there and the module
      # writes its records there.
      azure_dns_zone_resource_group = each.value.azure_dns_zone_resource_group
```

Add to the `provider_configs` object type in `static-files/specs/install/azure/variables.tf`:

```hcl
    azure_dns_zone_resource_group = string
```

and a line `azure_dns_zone_resource_group = ""` to each entry in `terraform.tfvars.example`.

- [ ] **Step 10: Commit**

```bash
git add static-files/deployment/network/azure_dns static-files/deployment/tests/network/azure_dns static-files/specs/install/azure
git commit -m "fix(azure_dns): write records in the DNS zone resource group, not the scope's"
```

---

### Task 3: `distribution/front-door` setup script

**Files:**
- Create: `static-files/deployment/distribution/front-door/setup`
- Create: `static-files/deployment/tests/distribution/front-door/setup_test.bats`
- Create: `static-files/deployment/tests/resources/azure_mocks/afd_endpoint/success.json`
- Create: `static-files/deployment/tests/resources/azure_mocks/afd_endpoint/not_found.json`

**Interfaces:**
- Consumes: `CONTEXT` (`.asset.url`, `.application.slug`, `.scope.slug`, `.scope.id`, `.providers["scope-configurations"]`), `RESOURCE_TAGS_JSON`, `MODULES_TO_USE`, `get_config_value`.
- Produces in `TOFU_VARIABLES`: `distribution_storage_account`, `distribution_container_name`, `distribution_blob_prefix`, `distribution_app_name`, `distribution_resource_tags_json`, `distribution_front_door_profile`, `distribution_front_door_endpoint`, `distribution_front_door_resource_group`. Task 5's `variables.tf` declares exactly these.
- Env fallbacks: `AZURE_FRONT_DOOR_PROFILE`, `AZURE_FRONT_DOOR_ENDPOINT`, `AZURE_FRONT_DOOR_RESOURCE_GROUP`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`.

- [ ] **Step 1: Write the mock fixtures**

`static-files/deployment/tests/resources/azure_mocks/afd_endpoint/success.json`:
```json
{
  "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-resource-group/providers/Microsoft.Cdn/profiles/shared-afd/afdEndpoints/shared-endpoint",
  "name": "shared-endpoint",
  "properties": {
    "hostName": "shared-endpoint-abcd.z01.azurefd.net",
    "enabledState": "Enabled",
    "provisioningState": "Succeeded"
  }
}
```

`static-files/deployment/tests/resources/azure_mocks/afd_endpoint/not_found.json`:
```json
{
  "error": {
    "code": "ResourceNotFound",
    "message": "The Resource 'Microsoft.Cdn/profiles/shared-afd/afdEndpoints/shared-endpoint' under resource group 'my-resource-group' was not found."
  }
}
```

- [ ] **Step 2: Write the failing BATS tests**

Create `static-files/deployment/tests/distribution/front-door/setup_test.bats`:

```bash
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
    "asset": {"url": "https://mystaticstorage.blob.core.windows.net/assets/tools/automation/v1.0.0"},
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
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')" "assets"
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')" "/tools/automation/v1.0.0"
}

@test "Should decode a URL-encoded \$web container" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/%24web/frontends/4/612605537"')

  run_front_door_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_container_name')" '$web'
  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_blob_prefix')" "/frontends/4/612605537"
}

@test "Should use root prefix when asset URL has no path after container" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.asset.url = "https://mystaticstorage.blob.core.windows.net/assets"')

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

@test "Should add distribution variables to TOFU_VARIABLES" {
  run_front_door_setup

  local expected='{
  "application_slug": "automation",
  "scope_slug": "development-tools",
  "scope_id": "7",
  "distribution_storage_account": "mystaticstorage",
  "distribution_container_name": "assets",
  "distribution_app_name": "automation-development-tools-7",
  "distribution_blob_prefix": "/tools/automation/v1.0.0",
  "distribution_resource_tags_json": {},
  "distribution_front_door_profile": "shared-afd",
  "distribution_front_door_endpoint": "shared-endpoint",
  "distribution_front_door_resource_group": "my-resource-group"
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
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bats static-files/deployment/tests/distribution/front-door/setup_test.bats`
Expected: every test FAILS with `No such file or directory` for the setup script.

- [ ] **Step 4: Write the setup script**

Create `static-files/deployment/distribution/front-door/setup` (mode 755):

```bash
#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/get_config_value"

echo "🔍 Validating Azure Front Door distribution configuration..."

application_slug=$(echo "$CONTEXT" | jq -r .application.slug)
scope_slug=$(echo "$CONTEXT" | jq -r .scope.slug)
scope_id=$(echo "$CONTEXT" | jq -r .scope.id)
asset_url=$(echo "$CONTEXT" | jq -r .asset.url)

distribution_app_name="$application_slug-$scope_slug-$scope_id"
echo "   ✅ app_name=$distribution_app_name"

# =============================================================================
# Asset location
# Format: https://<account>.blob.core.windows.net/<container>/<prefix>
# CI may percent-encode the container ($web arrives as %24web).
# =============================================================================
if [[ "$asset_url" == https://*.blob.core.windows.net/* ]]; then
  url_without_scheme="${asset_url#https://}"
  distribution_storage_account="${url_without_scheme%%.*}"
  url_path="${url_without_scheme#*/}"
  distribution_container_name="${url_path%%/*}"
  distribution_container_name="${distribution_container_name//%24/\$}"
  remaining_path="${url_path#*/}"
  if [ "$remaining_path" = "$url_path" ]; then
    distribution_blob_prefix="/"
  else
    distribution_blob_prefix="/${remaining_path}"
  fi
else
  echo ""
  echo "   ❌ Could not extract storage account from asset URL: $asset_url"
  echo ""
  echo "  💡 Possible causes:"
  echo "    • The asset URL format is not recognized"
  echo "    • CI registered the asset with something other than the blob URL"
  echo ""
  echo "  🔧 How to fix:"
  echo "    • Register the asset with 'https://<account>.blob.core.windows.net/<container>/<prefix>'"
  echo ""
  exit 1
fi

distribution_container_name=${distribution_container_name:-"\$web"}

echo "   ✅ storage_account=$distribution_storage_account"
echo "   ✅ container=$distribution_container_name"
echo "   ✅ blob_prefix=${distribution_blob_prefix:-"(root)"}"

# =============================================================================
# Shared Front Door profile and endpoint (customer-owned prerequisites)
# =============================================================================
missing_vars=()

distribution_front_door_profile=$(get_config_value \
  --provider '.providers["scope-configurations"].distribution.azure_front_door_profile' \
  --env AZURE_FRONT_DOOR_PROFILE)
if [ -z "$distribution_front_door_profile" ]; then
  echo "   ❌ azure_front_door_profile is missing"
  missing_vars+=("distribution.azure_front_door_profile")
else
  echo "   ✅ front_door_profile=$distribution_front_door_profile"
fi

distribution_front_door_endpoint=$(get_config_value \
  --provider '.providers["scope-configurations"].distribution.azure_front_door_endpoint' \
  --env AZURE_FRONT_DOOR_ENDPOINT)
if [ -z "$distribution_front_door_endpoint" ]; then
  echo "   ❌ azure_front_door_endpoint is missing"
  missing_vars+=("distribution.azure_front_door_endpoint")
else
  echo "   ✅ front_door_endpoint=$distribution_front_door_endpoint"
fi

if [ ${#missing_vars[@]} -gt 0 ]; then
  echo ""
  echo "  💡 Possible causes:"
  echo "    • The scope-configurations provider is missing these fields"
  echo ""
  echo "  🔧 How to fix:"
  echo "    Set the missing field(s) in the scope-configurations provider:"
  for var in "${missing_vars[@]}"; do
    echo "      • $var"
  done
  echo "    Or set AZURE_FRONT_DOOR_PROFILE / AZURE_FRONT_DOOR_ENDPOINT in the agent"
  echo ""
  exit 1
fi

provider_resource_group=$(get_config_value \
  --provider '.providers["scope-configurations"].provider.azure_resource_group' \
  --env AZURE_RESOURCE_GROUP)
distribution_front_door_resource_group=$(get_config_value \
  --provider '.providers["scope-configurations"].distribution.azure_front_door_resource_group' \
  --env AZURE_FRONT_DOOR_RESOURCE_GROUP \
  --default "$provider_resource_group")
echo "   ✅ front_door_resource_group=$distribution_front_door_resource_group"

subscription_id=$(get_config_value \
  --provider '.providers["scope-configurations"].provider.azure_subscription_id' \
  --env AZURE_SUBSCRIPTION_ID)

# =============================================================================
# Preflight: the shared endpoint must already exist
# =============================================================================
echo ""
echo "   📡 Verifying Front Door endpoint..."

endpoint_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${distribution_front_door_resource_group}/providers/Microsoft.Cdn/profiles/${distribution_front_door_profile}/afdEndpoints/${distribution_front_door_endpoint}?api-version=2025-04-15"

stderr_file=$(mktemp)
az_output=$(az rest --method get --url "$endpoint_url" 2>"$stderr_file") && az_exit_code=0 || az_exit_code=$?
az_stderr=$(cat "$stderr_file")
rm -f "$stderr_file"

if [ $az_exit_code -ne 0 ]; then
  echo ""
  if echo "$az_stderr" | grep -q "ResourceNotFound\|NotFound\|ParentResourceNotFound"; then
    echo "   ❌ Front Door endpoint '$distribution_front_door_endpoint' was not found in profile '$distribution_front_door_profile' (resource group '$distribution_front_door_resource_group')"
    echo ""
    echo "  💡 Possible causes:"
    echo "    • The shared profile or endpoint has not been created yet"
    echo "    • The names in the scope configuration have a typo"
    echo ""
    echo "  🔧 How to fix:"
    echo "    • Create them once per environment:"
    echo "        az afd profile create --resource-group $distribution_front_door_resource_group --profile-name $distribution_front_door_profile --sku Standard_AzureFrontDoor"
    echo "        az afd endpoint create --resource-group $distribution_front_door_resource_group --profile-name $distribution_front_door_profile --endpoint-name $distribution_front_door_endpoint --enabled-state Enabled"
  elif echo "$az_stderr" | grep -q "AuthorizationFailed\|Forbidden\|403"; then
    echo "   🔒 Error: Permission denied when reading the Front Door endpoint"
    echo ""
    echo "  🔧 How to fix:"
    echo "    • Grant the agent identity 'CDN Profile Contributor' on resource group '$distribution_front_door_resource_group'"
  else
    echo "   ❌ Failed to read the Front Door endpoint"
    echo ""
    echo "  📋 Error details:"
    echo "$az_stderr" | sed 's/^/    /'
  fi
  echo ""
  exit 1
fi

endpoint_host=$(echo "$az_output" | jq -r '.properties.hostName // empty')
echo "   ✅ endpoint_host=${endpoint_host:-"(unknown)"}"

RESOURCE_TAGS_JSON=${RESOURCE_TAGS_JSON:-"{}"}

TOFU_VARIABLES=$(echo "$TOFU_VARIABLES" | jq \
  --arg storage_account "$distribution_storage_account" \
  --arg container_name "$distribution_container_name" \
  --arg app_name "$distribution_app_name" \
  --arg blob_prefix "$distribution_blob_prefix" \
  --argjson resource_tags_json "$RESOURCE_TAGS_JSON" \
  --arg fd_profile "$distribution_front_door_profile" \
  --arg fd_endpoint "$distribution_front_door_endpoint" \
  --arg fd_resource_group "$distribution_front_door_resource_group" \
  '. + {
    distribution_storage_account: $storage_account,
    distribution_container_name: $container_name,
    distribution_app_name: $app_name,
    distribution_blob_prefix: $blob_prefix,
    distribution_resource_tags_json: $resource_tags_json,
    distribution_front_door_profile: $fd_profile,
    distribution_front_door_endpoint: $fd_endpoint,
    distribution_front_door_resource_group: $fd_resource_group
  }')

echo ""
echo "✨ Azure Front Door distribution configured successfully"
echo ""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
module_name="${script_dir}/modules"

if [[ -n $MODULES_TO_USE ]]; then
  MODULES_TO_USE="$MODULES_TO_USE,$module_name"
else
  MODULES_TO_USE="$module_name"
fi
```

Run `chmod +x static-files/deployment/distribution/front-door/setup`.

- [ ] **Step 5: Run the BATS tests**

Run: `bats static-files/deployment/tests/distribution/front-door/setup_test.bats`
Expected: 14 tests PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck -x static-files/deployment/distribution/front-door/setup`
Expected: no findings (the repo's CI runs shellcheck on every script).

- [ ] **Step 7: Commit**

```bash
git add static-files/deployment/distribution/front-door/setup static-files/deployment/tests/distribution/front-door static-files/deployment/tests/resources/azure_mocks/afd_endpoint
git commit -m "feat(distribution): add front-door setup script"
```

---

### Task 4: `distribution/front-door` module, origin and route

**Files:**
- Create: `static-files/deployment/distribution/front-door/modules/variables.tf`
- Create: `static-files/deployment/distribution/front-door/modules/data.tf`
- Create: `static-files/deployment/distribution/front-door/modules/locals.tf`
- Create: `static-files/deployment/distribution/front-door/modules/main.tf`
- Create: `static-files/deployment/distribution/front-door/modules/outputs.tf`
- Create: `static-files/deployment/distribution/front-door/modules/test_locals.tf`
- Create: `static-files/deployment/distribution/front-door/modules/test_versions.tf`
- Create: `static-files/deployment/distribution/front-door/modules/front-door.tftest.hcl`

**Interfaces:**
- Consumes: the `TOFU_VARIABLES` keys from Task 3; `var.azure_provider` (from `provider/azure`); `local.network_full_domain`, `local.network_domain` (from `network/azure_dns`); `var.network_subdomain`, `var.network_dns_zone_name`, `var.network_dns_zone_resource_group` (Task 2).
- Produces: `local.distribution_target_domain`, `local.distribution_record_type = "CNAME"`, `local.distribution_origin_path`, resources `azurerm_cdn_frontdoor_origin_group.static`, `azurerm_cdn_frontdoor_origin.static`, `azurerm_cdn_frontdoor_rule_set.static`, `azurerm_cdn_frontdoor_rule.spa_fallback`, `azurerm_cdn_frontdoor_rule.static_cache`, `azurerm_cdn_frontdoor_route.static`. Task 5 adds the custom domain, TXT, association and purge to the same files.

- [ ] **Step 1: Write the variables**

`static-files/deployment/distribution/front-door/modules/variables.tf`:

```hcl
variable "distribution_storage_account" {
  description = "Azure Storage account that hosts the static website ($web) with the bundles"
  type        = string
}

variable "distribution_container_name" {
  description = "Blob container the asset URL points to (informational; the origin is the static-website host)"
  type        = string
  default     = "$web"
}

variable "distribution_blob_prefix" {
  description = "Blob path prefix for this scope's files (e.g. '/frontends/4/612605537')"
  type        = string
  default     = "/"
}

variable "distribution_app_name" {
  description = "Base name for every resource this scope creates (<app>-<scope>-<id>)"
  type        = string
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}

variable "distribution_front_door_profile" {
  description = "Name of the shared Front Door profile (customer-owned, read only)"
  type        = string
}

variable "distribution_front_door_endpoint" {
  description = "Name of the shared Front Door endpoint inside the profile (customer-owned, read only)"
  type        = string
}

variable "distribution_front_door_resource_group" {
  description = "Resource group that holds the shared Front Door profile"
  type        = string
}
```

- [ ] **Step 2: Write the data sources**

`static-files/deployment/distribution/front-door/modules/data.tf`:

```hcl
data "azurerm_storage_account" "static" {
  name                = var.distribution_storage_account
  resource_group_name = var.azure_provider.resource_group
}

# The profile and the endpoint are prerequisites the customer creates once per
# environment. The scope never creates, updates or destroys them.
data "azurerm_cdn_frontdoor_profile" "shared" {
  name                = var.distribution_front_door_profile
  resource_group_name = var.distribution_front_door_resource_group
}

data "azurerm_cdn_frontdoor_endpoint" "shared" {
  name                = var.distribution_front_door_endpoint
  profile_name        = var.distribution_front_door_profile
  resource_group_name = var.distribution_front_door_resource_group
}
```

- [ ] **Step 3: Write the locals**

`static-files/deployment/distribution/front-door/modules/locals.tf`:

```hcl
locals {
  distribution_full_domain       = local.network_full_domain
  distribution_has_custom_domain = local.network_full_domain != ""

  distribution_blob_prefix_trimmed = trim(var.distribution_blob_prefix, "/")
  distribution_origin_path         = local.distribution_blob_prefix_trimmed != "" ? "/${local.distribution_blob_prefix_trimmed}" : ""

  # Rule sets and rules only accept letters and digits, and at most 60 chars.
  # "<app>-<scope>-<id>" has hyphens, so strip them and cap the length.
  distribution_rule_set_name = substr(replace(var.distribution_app_name, "/[^A-Za-z0-9]/", ""), 0, 60)

  distribution_tags = merge(var.distribution_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = "distribution/front-door"
  })

  distribution_compressed_content_types = [
    "application/javascript",
    "application/json",
    "application/xml",
    "application/x-javascript",
    "image/svg+xml",
    "text/css",
    "text/html",
    "text/javascript",
    "text/plain",
    "text/xml",
  ]

  # Cross-module references (consumed by network/azure_dns): the CNAME points
  # at the shared endpoint; Front Door then routes by Host header.
  distribution_target_domain = data.azurerm_cdn_frontdoor_endpoint.shared.host_name
  distribution_record_type   = "CNAME"
}
```

- [ ] **Step 4: Write the resources**

`static-files/deployment/distribution/front-door/modules/main.tf`:

```hcl
# =============================================================================
# Azure Front Door distribution
#
# Inside a customer-owned profile and endpoint, this scope owns: an origin
# group, an origin (the storage static-website host), a rule set, a route and
# (Task 5) a custom domain with its validation record. Nothing here touches
# the profile or the endpoint themselves.
# =============================================================================

resource "azurerm_cdn_frontdoor_origin_group" "static" {
  name                     = "${var.distribution_app_name}-og"
  cdn_frontdoor_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id

  load_balancing {
    additional_latency_in_milliseconds = 0
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "static" {
  name                          = "${var.distribution_app_name}-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static.id
  enabled                       = true

  host_name                      = data.azurerm_storage_account.static.primary_web_host
  origin_host_header             = data.azurerm_storage_account.static.primary_web_host
  certificate_name_check_enabled = true
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_rule_set" "static" {
  name                     = local.distribution_rule_set_name
  cdn_frontdoor_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id
}

# SPA routing: a request without a file extension (a client-side route) is
# served index.html. Same rule blob-cdn carried, in Front Door terms.
resource "azurerm_cdn_frontdoor_rule" "spa_fallback" {
  depends_on = [azurerm_cdn_frontdoor_origin_group.static, azurerm_cdn_frontdoor_origin.static]

  name                      = "SpaFallback"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.static.id
  order                     = 1
  behavior_on_match         = "Continue"

  conditions {
    url_file_extension_condition {
      operator     = "LessThan"
      match_values = ["1"]
    }
  }

  actions {
    url_rewrite_action {
      source_pattern          = "/"
      destination             = "/index.html"
      preserve_unmatched_path = false
    }
  }
}

# Long cache for fingerprinted assets under /static/, as blob-cdn did.
resource "azurerm_cdn_frontdoor_rule" "static_cache" {
  depends_on = [azurerm_cdn_frontdoor_origin_group.static, azurerm_cdn_frontdoor_origin.static]

  name                      = "StaticCache"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.static.id
  order                     = 2
  behavior_on_match         = "Continue"

  conditions {
    url_path_condition {
      operator     = "BeginsWith"
      match_values = ["/static/"]
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior = "OverrideAlways"
      cache_duration = "7.00:00:00"
    }
  }
}

resource "azurerm_cdn_frontdoor_route" "static" {
  name                          = var.distribution_app_name
  cdn_frontdoor_endpoint_id     = data.azurerm_cdn_frontdoor_endpoint.shared.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.static.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.static.id]
  enabled                       = true

  # The version switch: a new deployment changes the origin path and the
  # purge below drops the old content from the edge.
  cdn_frontdoor_origin_path = local.distribution_origin_path

  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  # The endpoint is shared by every scope of the environment, so a route can
  # never own its default hostname. The custom domain is the scope's identity.
  link_to_default_domain          = false
  cdn_frontdoor_custom_domain_ids = local.distribution_custom_domain_ids

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = local.distribution_compressed_content_types
  }
}
```

`local.distribution_custom_domain_ids` is defined in Task 5. Until then, add this temporary line to `locals.tf` so the module plans: `distribution_custom_domain_ids = []` (Task 5 replaces it).

- [ ] **Step 5: Write the outputs**

`static-files/deployment/distribution/front-door/modules/outputs.tf`:

```hcl
output "distribution_storage_account" {
  description = "Azure Storage account name"
  value       = var.distribution_storage_account
}

output "distribution_container_name" {
  description = "Azure Storage container name"
  value       = var.distribution_container_name
}

output "distribution_blob_prefix" {
  description = "Blob prefix path for this scope"
  value       = var.distribution_blob_prefix
}

output "distribution_front_door_profile" {
  description = "Shared Front Door profile name"
  value       = var.distribution_front_door_profile
}

output "distribution_front_door_endpoint_hostname" {
  description = "Shared Front Door endpoint hostname (CNAME target)"
  value       = data.azurerm_cdn_frontdoor_endpoint.shared.host_name
}

output "distribution_route_name" {
  description = "Front Door route owned by this scope"
  value       = azurerm_cdn_frontdoor_route.static.name
}

output "distribution_target_domain" {
  description = "Target domain for DNS records (shared endpoint hostname)"
  value       = local.distribution_target_domain
}

output "distribution_record_type" {
  description = "DNS record type (CNAME for Front Door)"
  value       = local.distribution_record_type
}

output "distribution_website_url" {
  description = "Website URL (custom domain only; the shared endpoint hostname does not serve this scope)"
  value       = "https://${local.distribution_full_domain}"
}
```

- [ ] **Step 6: Write the test-only files**

`static-files/deployment/distribution/front-door/modules/test_locals.tf`:

```hcl
# =============================================================================
# Test-only locals and variables
#
# Bridges the network_* locals and the provider variables that the composed
# root module gets from network/azure_dns and provider/azure. Skipped by
# compose_modules (test_*.tf).
# =============================================================================

variable "network_full_domain" {
  description = "Test-only: full domain from the network layer"
  type        = string
  default     = ""
}

variable "network_domain" {
  description = "Test-only: root domain from the network layer"
  type        = string
  default     = ""
}

variable "network_subdomain" {
  description = "Subdomain for the distribution"
  type        = string
  default     = ""
}

variable "network_dns_zone_name" {
  description = "Azure DNS zone name"
  type        = string
  default     = ""
}

variable "network_dns_zone_resource_group" {
  description = "Resource group of the Azure DNS zone"
  type        = string
  default     = ""
}

variable "azure_provider" {
  description = "Azure provider configuration"
  type = object({
    subscription_id = string
    resource_group  = string
    storage_account = string
    container       = string
  })
}

locals {
  network_full_domain = var.network_full_domain
  network_domain      = var.network_domain
}
```

`static-files/deployment/distribution/front-door/modules/test_versions.tf`: same content as Task 2 Step 6.

- [ ] **Step 7: Write the failing tofu tests**

`static-files/deployment/distribution/front-door/modules/front-door.tftest.hcl`:

```hcl
# =============================================================================
# Unit tests for distribution/front-door module
#
# Run: tofu test
# =============================================================================

mock_provider "azurerm" {
  mock_data "azurerm_storage_account" {
    defaults = {
      primary_web_host = "mystaticstorage.z13.web.core.windows.net"
    }
  }

  mock_data "azurerm_cdn_frontdoor_profile" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd"
      sku_name = "Standard_AzureFrontDoor"
    }
  }

  mock_data "azurerm_cdn_frontdoor_endpoint" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/shared-afd/afdEndpoints/shared-endpoint"
      host_name = "shared-endpoint-abcd.z01.azurefd.net"
    }
  }

  mock_data "azurerm_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/dnszones/example.com"
    }
  }
}

variables {
  distribution_storage_account           = "mystaticstorage"
  distribution_container_name            = "$web"
  distribution_blob_prefix               = "frontends/4/612605537"
  distribution_app_name                  = "automation-development-tools-7"
  distribution_front_door_profile        = "shared-afd"
  distribution_front_door_endpoint       = "shared-endpoint"
  distribution_front_door_resource_group = "cdn-rg"
  distribution_resource_tags_json = {
    Environment = "production"
  }
  network_full_domain             = "automation-development-tools.example.com"
  network_domain                  = "example.com"
  network_subdomain               = "automation-development-tools"
  network_dns_zone_name           = "example.com"
  network_dns_zone_resource_group = "dns-rg"
  azure_provider = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    resource_group  = "my-resource-group"
    storage_account = "mytfstatestorage"
    container       = "tfstate"
  }
}

run "origin_points_to_static_website_host" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_origin.static.host_name == "mystaticstorage.z13.web.core.windows.net"
    error_message = "Origin host should be the storage account static-website host"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_origin.static.origin_host_header == "mystaticstorage.z13.web.core.windows.net"
    error_message = "Origin host header should match the origin host"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.static.name == "automation-development-tools-7-og"
    error_message = "Origin group name should be '<app_name>-og'"
  }
}

run "route_uses_origin_path_and_custom_domain_only" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.cdn_frontdoor_origin_path == "/frontends/4/612605537"
    error_message = "Route origin path should be the normalized blob prefix"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.link_to_default_domain == false
    error_message = "Route must not be linked to the shared endpoint's default domain"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.https_redirect_enabled == true
    error_message = "Route should redirect HTTP to HTTPS"
  }

  assert {
    condition     = azurerm_cdn_frontdoor_route.static.forwarding_protocol == "HttpsOnly"
    error_message = "Route should forward to the origin over HTTPS only"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_route.static.cache).compression_enabled == true
    error_message = "Route cache should enable compression"
  }
}

run "origin_path_normalizes_leading_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "/app"
  }

  assert {
    condition     = local.distribution_origin_path == "/app"
    error_message = "Origin path should be '/app'"
  }
}

run "origin_path_handles_empty" {
  command = plan

  variables {
    distribution_blob_prefix = ""
  }

  assert {
    condition     = local.distribution_origin_path == ""
    error_message = "Origin path should be empty when prefix is empty"
  }
}

run "origin_path_trims_trailing_slash" {
  command = plan

  variables {
    distribution_blob_prefix = "/app/subfolder/"
  }

  assert {
    condition     = local.distribution_origin_path == "/app/subfolder"
    error_message = "Origin path should trim trailing slashes"
  }
}

run "rule_set_name_is_alphanumeric_and_short" {
  command = plan

  variables {
    distribution_app_name = "very-long-application-slug-with-many-words-and-a-long-scope-name-123456"
  }

  assert {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,59}$", azurerm_cdn_frontdoor_rule_set.static.name))
    error_message = "Rule set name must be letters and digits only, at most 60 chars, got '${azurerm_cdn_frontdoor_rule_set.static.name}'"
  }
}

run "spa_fallback_rule_rewrites_to_index" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_rule.spa_fallback.order == 1
    error_message = "SPA fallback should be the first rule"
  }

  assert {
    condition     = one(one(azurerm_cdn_frontdoor_rule.spa_fallback.actions).url_rewrite_action).destination == "/index.html"
    error_message = "SPA fallback should rewrite to /index.html"
  }
}

run "cross_module_locals_for_dns" {
  command = plan

  assert {
    condition     = local.distribution_record_type == "CNAME"
    error_message = "Record type should be CNAME"
  }

  assert {
    condition     = local.distribution_target_domain == "shared-endpoint-abcd.z01.azurefd.net"
    error_message = "DNS target should be the shared endpoint hostname"
  }
}

run "website_url_is_the_custom_domain" {
  command = plan

  assert {
    condition     = output.distribution_website_url == "https://automation-development-tools.example.com"
    error_message = "Website URL should be the custom domain"
  }
}
```

- [ ] **Step 8: Run the tofu tests**

Run:
```bash
cd static-files/deployment/distribution/front-door/modules && rm -rf .terraform .terraform.lock.hcl && tofu init -backend=false -input=false >/dev/null && tofu test
```
Expected: all runs PASS. If `tofu init` installs an azurerm other than 3.117.x, `test_versions.tf` is missing or malformed.

- [ ] **Step 9: Commit**

```bash
git add static-files/deployment/distribution/front-door/modules
git commit -m "feat(distribution): front-door module with origin, rule set and route"
```

---

### Task 5: Custom domain, validation record, association and purge

**Files:**
- Modify: `static-files/deployment/distribution/front-door/modules/data.tf`
- Modify: `static-files/deployment/distribution/front-door/modules/locals.tf`
- Modify: `static-files/deployment/distribution/front-door/modules/main.tf`
- Modify: `static-files/deployment/distribution/front-door/modules/outputs.tf`
- Modify: `static-files/deployment/distribution/front-door/modules/front-door.tftest.hcl`

**Interfaces:**
- Consumes: `var.network_dns_zone_name`, `var.network_dns_zone_resource_group`, `var.network_subdomain`, `local.network_full_domain`, `var.azure_provider.subscription_id`.
- Produces: `azurerm_cdn_frontdoor_custom_domain.static`, `azurerm_dns_txt_record.custom_domain_validation`, `azurerm_cdn_frontdoor_custom_domain_association.static`, `terraform_data.front_door_purge`, `local.distribution_custom_domain_ids`.

- [ ] **Step 1: Write the failing tofu tests**

Append to `front-door.tftest.hcl`:

```hcl
run "custom_domain_with_managed_certificate" {
  command = plan

  assert {
    condition     = azurerm_cdn_frontdoor_custom_domain.static.host_name == "automation-development-tools.example.com"
    error_message = "Custom domain host should be the network full domain"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_custom_domain.static.tls).certificate_type == "ManagedCertificate"
    error_message = "Custom domain should use a managed certificate"
  }

  assert {
    condition     = one(azurerm_cdn_frontdoor_custom_domain.static.tls).minimum_tls_version == "TLS12"
    error_message = "Custom domain should require TLS 1.2"
  }
}

run "validation_txt_record_in_dns_zone_resource_group" {
  command = plan

  assert {
    condition     = azurerm_dns_txt_record.custom_domain_validation.name == "_dnsauth.automation-development-tools"
    error_message = "Validation record should be _dnsauth.<subdomain>"
  }

  assert {
    condition     = azurerm_dns_txt_record.custom_domain_validation.zone_name == "example.com"
    error_message = "Validation record should live in the network DNS zone"
  }

  assert {
    condition     = azurerm_dns_txt_record.custom_domain_validation.resource_group_name == "dns-rg"
    error_message = "Validation record should be created in the DNS zone resource group"
  }
}

run "route_is_associated_with_the_custom_domain" {
  command = plan

  assert {
    condition     = length(azurerm_cdn_frontdoor_route.static.cdn_frontdoor_custom_domain_ids) == 1
    error_message = "Route should reference exactly one custom domain"
  }

  assert {
    condition     = length(azurerm_cdn_frontdoor_custom_domain_association.static.cdn_frontdoor_route_ids) == 1
    error_message = "Association should reference the scope's route"
  }
}

run "purge_is_scoped_to_the_custom_domain" {
  command = plan

  assert {
    condition     = strcontains(local.distribution_purge_command, "afdEndpoints/shared-endpoint/purge?api-version=2025-04-15")
    error_message = "Purge should target the shared endpoint purge action"
  }

  assert {
    condition     = strcontains(local.distribution_purge_command, "\"domains\":[\"automation-development-tools.example.com\"]")
    error_message = "Purge should be filtered by this scope's domain"
  }

  assert {
    condition     = terraform_data.front_door_purge.triggers_replace[0] == "/frontends/4/612605537"
    error_message = "Purge should re-run when the origin path changes"
  }
}

run "fails_without_custom_domain" {
  command = plan

  variables {
    network_full_domain = ""
    network_subdomain   = ""
  }

  expect_failures = [
    azurerm_cdn_frontdoor_custom_domain.static,
  ]
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd static-files/deployment/distribution/front-door/modules && tofu test`
Expected: the five new runs FAIL with `Reference to undeclared resource`.

- [ ] **Step 3: Add the DNS zone data source**

Append to `data.tf`:

```hcl
# The zone the custom domain lives in. Front Door validates the domain with a
# TXT record here, so the module needs the zone id and writes into it.
data "azurerm_dns_zone" "custom_domain" {
  name                = var.network_dns_zone_name
  resource_group_name = var.network_dns_zone_resource_group
}
```

- [ ] **Step 4: Replace the temporary local and add the purge command**

In `locals.tf`, delete `distribution_custom_domain_ids = []` and add inside the `locals` block:

```hcl
  distribution_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.static.id]

  distribution_purge_url = "https://management.azure.com${data.azurerm_cdn_frontdoor_endpoint.shared.id}/purge?api-version=2025-04-15"

  # Purge only this scope's domain: the endpoint is shared with every other
  # scope of the environment.
  distribution_purge_command = "az rest --method post --url '${local.distribution_purge_url}' --body '${jsonencode({ contentPaths = ["/*"], domains = [local.distribution_full_domain] })}'"
```

- [ ] **Step 5: Add the resources**

Append to `main.tf`:

```hcl
# =============================================================================
# Custom domain: mandatory. The route is not reachable through the shared
# endpoint hostname, so without a DNS zone there is nothing to serve.
# =============================================================================
resource "azurerm_cdn_frontdoor_custom_domain" "static" {
  name                     = "${var.distribution_app_name}-domain"
  cdn_frontdoor_profile_id = data.azurerm_cdn_frontdoor_profile.shared.id
  dns_zone_id              = data.azurerm_dns_zone.custom_domain.id
  host_name                = local.distribution_full_domain

  tls {
    certificate_type    = "ManagedCertificate"
    minimum_tls_version = "TLS12"
  }

  lifecycle {
    precondition {
      condition     = local.distribution_has_custom_domain
      error_message = "The front-door distribution needs a custom domain: configure the network layer (network.azure_network = azure_dns with a DNS zone) for this scope."
    }
  }
}

# Front Door proves domain ownership through _dnsauth.<subdomain> holding the
# validation token. The managed certificate is issued once this resolves.
resource "azurerm_dns_txt_record" "custom_domain_validation" {
  name                = "_dnsauth.${var.network_subdomain}"
  zone_name           = var.network_dns_zone_name
  resource_group_name = var.network_dns_zone_resource_group
  ttl                 = 3600

  record {
    value = azurerm_cdn_frontdoor_custom_domain.static.validation_token
  }
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "static" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.static.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.static.id]
}

# Drop the previous version from the edge whenever the origin path changes.
# Same role as the CloudFront invalidation, scoped to this domain because the
# endpoint is shared.
resource "terraform_data" "front_door_purge" {
  triggers_replace = [
    local.distribution_origin_path
  ]

  provisioner "local-exec" {
    command = local.distribution_purge_command
  }

  depends_on = [
    azurerm_cdn_frontdoor_route.static,
    azurerm_cdn_frontdoor_custom_domain_association.static,
  ]
}
```

- [ ] **Step 6: Add the outputs**

Append to `outputs.tf`:

```hcl
output "distribution_custom_domain" {
  description = "Custom domain served by this scope"
  value       = azurerm_cdn_frontdoor_custom_domain.static.host_name
}

output "distribution_validation_record" {
  description = "TXT record that validates the custom domain"
  value       = azurerm_dns_txt_record.custom_domain_validation.fqdn
}
```

- [ ] **Step 7: Run the tofu tests**

Run: `cd static-files/deployment/distribution/front-door/modules && tofu test`
Expected: every run PASS, including `fails_without_custom_domain` (reported as passing because the failure was expected).

- [ ] **Step 8: Commit**

```bash
git add static-files/deployment/distribution/front-door/modules
git commit -m "feat(distribution): front-door custom domain, validation record and purge"
```

---

### Task 6: Scope configuration schema and UI

**Files:**
- Modify: `static-files/specs/scope-configuration.json.tpl` (the azure `then` branch at lines 46-58, `azure_distribution` at 240-251, the Azure agent-credentials label at 789, the `azure_distribution` control at 878-894)
- Test: `static-files/deployment/tests/specs/layer_selection_test.bats` (existing consistency tests)

**Interfaces:**
- Produces: `distribution.azure_front_door_profile`, `distribution.azure_front_door_endpoint`, `distribution.azure_front_door_resource_group`; `azure_distribution` enum `["front-door"]`. Read by Task 3's setup through `get_config_value`.

- [ ] **Step 1: Add a schema test for the new required fields**

Append to `static-files/deployment/tests/specs/layer_selection_test.bats`:

```bash
@test "Should require the Front Door profile and endpoint on the azure branch" {
	local required
	required=$(render_schema | jq -r '.schema.else.then.properties.distribution.required[]' | sort | tr '\n' ' ')

	assert_equal "$required" "azure_front_door_endpoint azure_front_door_profile "
}

@test "Should offer front-door as the only azure distribution" {
	local values
	values=$(render_schema | jq -r '.schema.properties.distribution.properties.azure_distribution.oneOf[].const' | tr '\n' ' ')

	assert_equal "$values" "front-door "
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bats static-files/deployment/tests/specs/layer_selection_test.bats`
Expected: the two new tests FAIL (`blob-cdn` vs `front-door`, empty required list).

- [ ] **Step 3: Edit the schema**

In the azure `then` branch (the object at lines 47-58 with `"provider": { "required": [...] }`), add a sibling:

```json
          "distribution": {
            "required": [
              "azure_front_door_profile",
              "azure_front_door_endpoint"
            ]
          }
```

Replace the `azure_distribution` property (lines 240-251) with:

```json
          "azure_distribution": {
            "type": "string",
            "title": "Azure Distribution",
            "description": "CDN distribution for serving static files",
            "default": "front-door",
            "oneOf": [
              {
                "const": "front-door",
                "title": "Azure Front Door (Standard/Premium)"
              }
            ]
          },
          "azure_front_door_profile": {
            "type": "string",
            "title": "Front Door Profile",
            "description": "Name of the shared Front Door profile for this environment. Created once by your platform team; the scope only adds routes to it."
          },
          "azure_front_door_endpoint": {
            "type": "string",
            "title": "Front Door Endpoint",
            "description": "Name of the shared endpoint inside the profile. Every scope of this environment gets a route and a custom domain on it."
          },
          "azure_front_door_resource_group": {
            "type": "string",
            "title": "Front Door Resource Group",
            "description": "Resource group that holds the profile. Leave empty to use the provider resource group."
          },
```

Replace the Azure agent-credentials label text (line 789) with:

```
> **ℹ️ Agent Credentials**\n\nThe nullplatform agent must run with Azure credentials configured. Use one of:\n\n- **Workload Identity** — attach an Azure managed identity to the agent's Kubernetes service account\n- **Service Principal** — set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID as environment variables in the agent Helm installation\n\nThe identity needs the following permissions:\n\n- **Storage Blob Data Contributor** — state backend\n- **DNS Zone Contributor** — CNAME and validation TXT records\n- **CDN Profile Contributor** on the Front Door resource group — routes, origins, custom domains and purge on the shared profile\n- **Reader** on the assets storage account\n\n**Prerequisites per environment:** a Front Door profile (Standard or Premium) and one endpoint in it, an Azure DNS zone, and a storage account with the static website enabled.
```

After the `azure_distribution` control (lines 878-894), add three controls with the same HIDE rule:

```json
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/distribution/properties/azure_front_door_profile"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/distribution/properties/azure_front_door_endpoint"
                },
                {
                  "rule": {
                    "effect": "HIDE",
                    "condition": {
                      "scope": "#/properties/cloud_provider",
                      "schema": { "not": { "const": "azure" } }
                    }
                  },
                  "type": "Control",
                  "scope": "#/properties/distribution/properties/azure_front_door_resource_group"
                },
```

- [ ] **Step 4: Run the consistency tests**

Run: `bats static-files/deployment/tests/specs/layer_selection_test.bats`
Expected: all PASS. `Should map every schema layer value to an implementation directory` passes because `distribution/front-door/setup` exists (Task 3) and `blob-cdn` is no longer in the enum.

- [ ] **Step 5: Commit**

```bash
git add static-files/specs/scope-configuration.json.tpl static-files/deployment/tests/specs/layer_selection_test.bats
git commit -m "feat(specs): configure the shared Front Door profile and endpoint"
```

---

### Task 7: Remove the `blob-cdn` layer

**Files:**
- Delete: `static-files/deployment/distribution/blob-cdn/` (whole directory)
- Delete: `static-files/deployment/tests/distribution/blob-cdn/`
- Delete: `static-files/deployment/tests/integration/test_cases/azure_blobcdn_azuredns/` (after Task 9 copies its DNS assertions)
- Modify: `static-files/specs/install/azure/main.tf:1468-1471`
- Modify: `static-files/README.md` (lines 45, 145-171, 175-190, 201, 511, 708, 747, 794-843, 902, 996-1002)
- Modify: `static-files/specs/install/README.md` (Azure paragraph)

**Interfaces:**
- Consumes: nothing from `blob-cdn` remains referenced after this task; `grep -rn "blob-cdn\|blob_cdn\|blobcdn" --exclude-dir=.git .` returns only `CHANGELOG.md` and `docs/`.

- [ ] **Step 1: Delete the layer and its unit tests**

```bash
git rm -r static-files/deployment/distribution/blob-cdn static-files/deployment/tests/distribution/blob-cdn
```

- [ ] **Step 2: Update the install reference**

In `static-files/specs/install/azure/main.tf` replace the `distribution` block of the provider config with:

```hcl
    distribution = {
      azure_distribution              = "front-door"
      azure_front_door_profile        = each.value.azure_front_door_profile
      azure_front_door_endpoint       = each.value.azure_front_door_endpoint
      azure_front_door_resource_group = coalesce(each.value.azure_front_door_resource_group, each.value.azure_resource_group)
    }
```

In `static-files/specs/install/azure/variables.tf` add to the `provider_configs` object type:

```hcl
    azure_front_door_profile        = string
    azure_front_door_endpoint       = string
    azure_front_door_resource_group = optional(string)
```

and extend its description with: `azure_front_door_profile` and `azure_front_door_endpoint` name the Front Door profile and endpoint shared by every static-files scope of that environment; create them before the first deployment.

In `terraform.tfvars.example` add to each entry:

```hcl
    azure_front_door_profile  = "" # shared per environment, e.g. "sf-dev-afd"
    azure_front_door_endpoint = "" # e.g. "sf-dev"
```

- [ ] **Step 3: Validate the install example**

Run: `cd static-files/specs/install/azure && tofu init -backend=false -input=false >/dev/null && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Rewrite the Azure parts of the README**

In `static-files/README.md`:

1. Line 45 of the layer diagram: replace `• blob-cdn` with `• front-door`.
2. In "Pre-requisites", replace item 3 (storage account) and item 4 (RBAC) and the two paragraphs that follow ("No certificate pre-requisite" and "Asset publishing is not solved yet on Azure") with:

```markdown
3. **A storage account with the static website feature enabled**, where CI
   uploads the frontend bundles. The distribution layer reads it with a data
   source and uses its `primary_web_host` as the Front Door origin. Set the
   error document to `index.html` as well as the index document:

   ```bash
   az storage blob service-properties update \
     --account-name <assets_storage_account> \
     --static-website --index-document index.html --404-document index.html
   ```

4. **A Front Door profile and one endpoint per environment.** Every
   static-files scope of that environment adds its own route and custom
   domain to this endpoint; the scope never creates or deletes the profile or
   the endpoint. The tier is chosen here, once:

   ```bash
   az afd profile create --resource-group <rg> --profile-name <profile> --sku Standard_AzureFrontDoor
   az afd endpoint create --resource-group <rg> --profile-name <profile> --endpoint-name <endpoint> --enabled-state Enabled
   ```

   Standard allows 100 custom domains and 100 routes per profile (Premium:
   500 and 200), which is the cap of scopes per environment.

5. **Azure RBAC role assignments for the agent's identity:**
   `Storage Blob Data Contributor` on the state storage account, `Reader` on the
   assets storage account, `DNS Zone Contributor` on the DNS zone, and
   `CDN Profile Contributor` on the resource group that holds the Front Door
   profile.

   > **`Contributor` on the resource group is not sufficient on its own.** It
   > grants the management plane but not the blob **data** plane, so the agent's
   > state writes still fail.

**No certificate pre-requisite.** The distribution layer requests a Front Door
managed certificate for the custom domain and writes the `_dnsauth` TXT record
that validates it. The domain answers once validation completes (a few minutes
on the first deployment).

**A DNS zone is mandatory on Azure.** The route is bound to the scope's custom
domain only; the shared endpoint hostname does not serve any scope.

**Publishing the bundle is CI's job**, the same way it is on AWS. Upload to the
static-website container and register the asset with the blob URL:

```bash
az storage blob upload-batch --account-name "$STORAGE_ACCOUNT" \
  --destination '$web' --destination-path "frontends/$application_id/$build_id" \
  --source ./dist --auth-mode login
np asset create --body "{\"type\":\"bundle\",\"name\":\"main\",\"build_id\":$build_id,
  \"application_id\":$application_id,
  \"url\":\"https://$STORAGE_ACCOUNT.blob.core.windows.net/\$web/frontends/$application_id/$build_id\",
  \"metadata\":{}}"
```
```

3. Line 201: replace `(Blob static website + CDN + Azure DNS), subject to the asset-publishing limitation described above.` with `(Blob static website + Front Door + Azure DNS).`
4. Line 511: `distribution/blob-cdn/modules/locals.tf` → `distribution/front-door/modules/locals.tf`.
5. Lines 708, 747: point to `tests/distribution/front-door/setup_test.bats` and `distribution/front-door/modules/front-door.tftest.hcl`.
6. Lines 794-843 (integration example): file name `azure_frontdoor_azuredns/lifecycle_test.bats`, `DISTRIBUTION_LAYER="front-door"`, assertion names `assert_azure_front_door_route_configured` / `assert_azure_front_door_route_not_configured` (Task 9).
7. Line 902: `# or: blob-cdn, amplify, firebase, etc.` → `# or: front-door`.
8. Lines 996-1002 (Quick Reference paths): replace every `blob-cdn` path with the `front-door` equivalent and the integration path with `azure_frontdoor_azuredns`.

In `static-files/specs/install/README.md`, replace the Azure bullet with:

```markdown
- **Azure** (`azure/`) — complete working example (Blob static website + Front
  Door + Azure DNS). Mirrors the shape of `aws/`. What varies per entry in
  `provider_configs` is the NRN, the resource group, the DNS zone and the shared
  Front Door profile and endpoint; the OpenTofu state storage account is shared,
  the same way `aws_state_bucket` is on AWS. The bundle is published by CI with
  `az storage blob upload-batch` + `np asset create`; see the top-level README.
```

- [ ] **Step 5: Check nothing else references the old layer**

Run: `grep -rn "blob-cdn\|blob_cdn\|blobcdn\|azureedge" --exclude-dir=.git --exclude-dir=testing --exclude=CHANGELOG.md --exclude-dir=docs .`
Expected: only `static-files/deployment/tests/integration/test_cases/azure_blobcdn_azuredns/` (deleted in Task 9 Step 1).

- [ ] **Step 6: Run the unit suites**

Run: `make test-unit && make test-tofu`
Expected: all PASS; no reference to a missing `blob-cdn` directory.

- [ ] **Step 7: Commit**

```bash
git add -A static-files/deployment/distribution static-files/deployment/tests/distribution static-files/specs/install static-files/README.md
git commit -m "feat(distribution)!: remove the retired Azure CDN classic (blob-cdn) layer

BREAKING CHANGE: azure_distribution no longer accepts blob-cdn. Azure CDN
Standard from Microsoft (classic) stopped accepting new profiles on
2025-08-15; use front-door with a shared profile and endpoint instead."
```

---

### Task 8: Azure mock learns Front Door (submodule `testing/`, repo `nullplatform/scope-testing`)

**Files (inside `testing/`):**
- Modify: `docker/azure-mock/main.go` (Store, models, regexes, dispatch, handlers)
- Create: `docker/azure-mock/main_test.go`

**Interfaces:**
- Produces HTTP behavior on the mock: PUT/GET/PATCH/DELETE for `.../profiles/{p}/afdEndpoints/{e}`, `.../afdEndpoints/{e}/routes/{r}`, `.../profiles/{p}/originGroups/{og}`, `.../originGroups/{og}/origins/{o}`, `.../profiles/{p}/ruleSets/{rs}`, `.../ruleSets/{rs}/rules/{r}`, `.../profiles/{p}/customDomains/{d}`; POST `.../afdEndpoints/{e}/purge`; PUT/GET/DELETE `.../dnszones/{z}/TXT/{name}`; `GET /mock/afd/purges` and `DELETE /mock/afd/purges`. Profile GET now returns `properties.frontDoorId`. Task 9 relies on all of these.

- [ ] **Step 1: Create a branch in the submodule**

```bash
cd testing && git checkout -q main && git pull -q && git checkout -b feat/azure-front-door-mock
```

- [ ] **Step 2: Write the failing Go test**

Create `testing/docker/azure-mock/main_test.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

const afdEndpointPath = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Cdn/profiles/shared-afd/afdEndpoints/shared-endpoint"

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	s := NewServer()
	return httptest.NewServer(s)
}

func doJSON(t *testing.T, method, url string, body interface{}) (*http.Response, map[string]interface{}) {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatal(err)
		}
	}
	req, _ := http.NewRequest(method, url, &buf)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]interface{}
	_ = json.NewDecoder(resp.Body).Decode(&out)
	resp.Body.Close()
	return resp, out
}

func TestAFDEndpointRoundTrip(t *testing.T) {
	srv := newTestServer(t)
	defer srv.Close()

	resp, created := doJSON(t, http.MethodPut, srv.URL+afdEndpointPath+"?api-version=2024-02-01",
		map[string]interface{}{"location": "global", "properties": map[string]interface{}{"enabledState": "Enabled"}})
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("PUT status = %d", resp.StatusCode)
	}
	props := created["properties"].(map[string]interface{})
	if props["hostName"] != "shared-endpoint-mock.z01.azurefd.net" {
		t.Fatalf("hostName = %v", props["hostName"])
	}
	if props["provisioningState"] != "Succeeded" {
		t.Fatalf("provisioningState = %v", props["provisioningState"])
	}

	resp, got := doJSON(t, http.MethodGet, srv.URL+afdEndpointPath, nil)
	if resp.StatusCode != http.StatusOK || got["name"] != "shared-endpoint" {
		t.Fatalf("GET status = %d name = %v", resp.StatusCode, got["name"])
	}

	resp, _ = doJSON(t, http.MethodDelete, srv.URL+afdEndpointPath, nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("DELETE status = %d", resp.StatusCode)
	}
	resp, _ = doJSON(t, http.MethodGet, srv.URL+afdEndpointPath, nil)
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("GET after DELETE status = %d", resp.StatusCode)
	}
}

func TestAFDCustomDomainExposesValidationToken(t *testing.T) {
	srv := newTestServer(t)
	defer srv.Close()

	path := "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Cdn/profiles/shared-afd/customDomains/app-domain"
	_, created := doJSON(t, http.MethodPut, srv.URL+path,
		map[string]interface{}{"properties": map[string]interface{}{"hostName": "app.example.com"}})
	props := created["properties"].(map[string]interface{})
	vp, ok := props["validationProperties"].(map[string]interface{})
	if !ok || vp["validationToken"] == "" {
		t.Fatalf("validationProperties missing: %v", props)
	}
	if props["domainValidationState"] != "Approved" {
		t.Fatalf("domainValidationState = %v", props["domainValidationState"])
	}
}

func TestAFDPurgeIsRecorded(t *testing.T) {
	srv := newTestServer(t)
	defer srv.Close()

	doJSON(t, http.MethodPut, srv.URL+afdEndpointPath, map[string]interface{}{"location": "global"})
	resp, _ := doJSON(t, http.MethodPost, srv.URL+afdEndpointPath+"/purge?api-version=2025-04-15",
		map[string]interface{}{"contentPaths": []string{"/*"}, "domains": []string{"app.example.com"}})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("purge status = %d", resp.StatusCode)
	}

	req, _ := http.NewRequest(http.MethodGet, srv.URL+"/mock/afd/purges", nil)
	r, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var purges []map[string]interface{}
	_ = json.NewDecoder(r.Body).Decode(&purges)
	r.Body.Close()
	if len(purges) != 1 {
		t.Fatalf("purges = %d", len(purges))
	}
	domains := purges[0]["domains"].([]interface{})
	if domains[0] != "app.example.com" {
		t.Fatalf("domains = %v", domains)
	}
}

func TestDNSTXTRecordRoundTrip(t *testing.T) {
	srv := newTestServer(t)
	defer srv.Close()

	path := "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/dnszones/example.com/TXT/_dnsauth.app"
	resp, created := doJSON(t, http.MethodPut, srv.URL+path,
		map[string]interface{}{"properties": map[string]interface{}{"TTL": 3600,
			"TXTRecords": []map[string]interface{}{{"value": []string{"token"}}}}})
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("PUT status = %d", resp.StatusCode)
	}
	if created["properties"].(map[string]interface{})["fqdn"] != "_dnsauth.app.example.com." {
		t.Fatalf("fqdn = %v", created["properties"])
	}
}
```

`NewServer()` (line 489) returns the `*Server` that `main()` passes to `http.ListenAndServe`; it implements `http.Handler` through `ServeHTTP` (line 495), which is where the dispatch `switch` of Step 5 lives.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd testing/docker/azure-mock && go test ./...`
Expected: FAIL (`404` on the AFD paths, no `/mock/afd/purges`).

- [ ] **Step 4: Add the store, models and regexes**

In `main.go`, add to `Store`:

```go
	// Azure Front Door Standard/Premium: generic ARM documents keyed by
	// lower-cased resource id. The provider only needs id/name/type,
	// provisioningState and a handful of kind-specific properties back.
	afdResources map[string]map[string]interface{}
	afdPurges    []AFDPurge
	dnsTXTRecords map[string]DNSTXTRecord
```

and initialize them in `NewStore()`:

```go
		afdResources:  make(map[string]map[string]interface{}),
		afdPurges:     []AFDPurge{},
		dnsTXTRecords: make(map[string]DNSTXTRecord),
```

Add the models next to the DNS ones:

```go
type AFDPurge struct {
	EndpointID   string   `json:"endpointId"`
	ContentPaths []string `json:"contentPaths"`
	Domains      []string `json:"domains"`
}

type DNSTXTRecord struct {
	ID         string            `json:"id"`
	Name       string            `json:"name"`
	Type       string            `json:"type"`
	Etag       string            `json:"etag,omitempty"`
	Properties DNSTXTRecordProps `json:"properties"`
}

type DNSTXTRecordProps struct {
	TTL        int             `json:"TTL"`
	Fqdn       string          `json:"fqdn,omitempty"`
	TXTRecords []DNSTXTValue   `json:"TXTRecords"`
}

type DNSTXTValue struct {
	Value []string `json:"value"`
}
```

Add `FrontDoorID string \`json:"frontDoorId,omitempty"\`` to `CDNProfileProps`, and in `handleCDNProfile`'s PUT set `FrontDoorID: "00000000-0000-0000-0000-00000000f00d"` inside the `Properties` literal.

Add the regexes to the `var (...)` block:

```go
	afdEndpointRegex      = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/afdEndpoints/[^/]+$`)
	afdEndpointPurgeRegex = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/afdEndpoints/[^/]+/purge$`)
	afdRouteRegex         = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/afdEndpoints/[^/]+/routes/[^/]+$`)
	afdOriginGroupRegex   = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/originGroups/[^/]+$`)
	afdOriginRegex        = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/originGroups/[^/]+/origins/[^/]+$`)
	afdRuleSetRegex       = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/ruleSets/[^/]+$`)
	afdRuleRegex          = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/ruleSets/[^/]+/rules/[^/]+$`)
	afdCustomDomainRegex  = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Cdn/profiles/[^/]+/customDomains/[^/]+$`)
	dnsTXTRecordRegex     = regexp.MustCompile(`(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/dnszones/[^/]+/TXT/[^/]+$`)
	mockAFDPurgesRegex    = regexp.MustCompile(`^/mock/afd/purges$`)
```

- [ ] **Step 5: Wire the dispatch**

In the `switch` inside `ServeHTTP`, insert before `case matchCDNOperationResults(path):`:

```go
	case mockAFDPurgesRegex.MatchString(path):
		s.handleMockAFDPurges(w, r)
	case afdEndpointPurgeRegex.MatchString(path):
		s.handleAFDPurge(w, r)
	case afdRouteRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/afdEndpoints/routes")
	case afdEndpointRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/afdEndpoints")
	case afdOriginRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/originGroups/origins")
	case afdOriginGroupRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/originGroups")
	case afdRuleRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/ruleSets/rules")
	case afdRuleSetRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/ruleSets")
	case afdCustomDomainRegex.MatchString(path):
		s.handleAFDResource(w, r, "Microsoft.Cdn/profiles/customDomains")
	case dnsTXTRecordRegex.MatchString(path):
		s.handleDNSTXTRecord(w, r)
```

- [ ] **Step 6: Write the handlers**

Append to `main.go`:

```go
// =============================================================================
// Azure Front Door Standard/Premium (generic ARM document handler)
// =============================================================================

func (s *Server) handleAFDResource(w http.ResponseWriter, r *http.Request, resourceType string) {
	resourceID := r.URL.Path
	key := strings.ToLower(resourceID)
	parts := strings.Split(resourceID, "/")
	name := parts[len(parts)-1]

	switch r.Method {
	case http.MethodPut, http.MethodPatch:
		var body map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			s.badRequest(w, "Invalid request body")
			return
		}

		s.store.mu.Lock()
		doc := body
		if r.Method == http.MethodPatch {
			existing, ok := s.store.afdResources[key]
			if !ok {
				s.store.mu.Unlock()
				s.resourceNotFound(w, resourceType, name)
				return
			}
			for k, v := range body {
				existing[k] = v
			}
			doc = existing
		}
		doc["id"] = resourceID
		doc["name"] = name
		doc["type"] = resourceType

		props, _ := doc["properties"].(map[string]interface{})
		if props == nil {
			props = map[string]interface{}{}
		}
		props["provisioningState"] = "Succeeded"
		props["deploymentStatus"] = "Succeeded"
		switch resourceType {
		case "Microsoft.Cdn/profiles/afdEndpoints":
			props["hostName"] = fmt.Sprintf("%s-mock.z01.azurefd.net", name)
			if _, ok := props["enabledState"]; !ok {
				props["enabledState"] = "Enabled"
			}
		case "Microsoft.Cdn/profiles/customDomains":
			props["domainValidationState"] = "Approved"
			props["validationProperties"] = map[string]interface{}{
				"validationToken": "mock-validation-token",
				"expirationDate":  "2030-01-01T00:00:00.0000000Z",
			}
			if _, ok := props["tlsSettings"]; !ok {
				props["tlsSettings"] = map[string]interface{}{
					"certificateType":   "ManagedCertificate",
					"minimumTlsVersion": "TLS12",
				}
			}
		}
		doc["properties"] = props
		s.store.afdResources[key] = doc
		s.store.mu.Unlock()

		if r.Method == http.MethodPut {
			w.WriteHeader(http.StatusCreated)
		}
		json.NewEncoder(w).Encode(doc)

	case http.MethodGet:
		s.store.mu.RLock()
		doc, exists := s.store.afdResources[key]
		s.store.mu.RUnlock()
		if !exists {
			s.resourceNotFound(w, resourceType, name)
			return
		}
		json.NewEncoder(w).Encode(doc)

	case http.MethodDelete:
		s.store.mu.Lock()
		delete(s.store.afdResources, key)
		// Children go with the parent (routes with an endpoint, origins with a group, rules with a set)
		for k := range s.store.afdResources {
			if strings.HasPrefix(k, key+"/") {
				delete(s.store.afdResources, k)
			}
		}
		s.store.mu.Unlock()
		w.WriteHeader(http.StatusOK)

	default:
		s.methodNotAllowed(w)
	}
}

func (s *Server) handleAFDPurge(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.methodNotAllowed(w)
		return
	}
	endpointID := strings.TrimSuffix(r.URL.Path, "/purge")

	var req struct {
		ContentPaths []string `json:"contentPaths"`
		Domains      []string `json:"domains"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.ContentPaths) == 0 {
		s.badRequest(w, "contentPaths is required")
		return
	}

	s.store.mu.Lock()
	_, exists := s.store.afdResources[strings.ToLower(endpointID)]
	if exists {
		s.store.afdPurges = append(s.store.afdPurges, AFDPurge{
			EndpointID: endpointID, ContentPaths: req.ContentPaths, Domains: req.Domains,
		})
	}
	s.store.mu.Unlock()

	if !exists {
		s.resourceNotFound(w, "Front Door Endpoint", endpointID)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// GET lists recorded purges, DELETE clears them. Test-only introspection.
func (s *Server) handleMockAFDPurges(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.store.mu.RLock()
		purges := append([]AFDPurge{}, s.store.afdPurges...)
		s.store.mu.RUnlock()
		json.NewEncoder(w).Encode(purges)
	case http.MethodDelete:
		s.store.mu.Lock()
		s.store.afdPurges = []AFDPurge{}
		s.store.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	default:
		s.methodNotAllowed(w)
	}
}

// =============================================================================
// DNS TXT Record Handler
// =============================================================================

func (s *Server) handleDNSTXTRecord(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	parts := strings.Split(path, "/")

	subscriptionID := parts[2]
	resourceGroup := parts[4]
	zoneName := parts[8]
	recordName := parts[10]

	resourceID := fmt.Sprintf("/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/dnszones/%s/TXT/%s",
		subscriptionID, resourceGroup, zoneName, recordName)

	switch r.Method {
	case http.MethodPut:
		var req struct {
			Properties DNSTXTRecordProps `json:"properties"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			s.badRequest(w, "Invalid request body")
			return
		}
		if len(req.Properties.TXTRecords) == 0 {
			s.badRequest(w, "TXTRecords is required")
			return
		}

		record := DNSTXTRecord{
			ID:   resourceID,
			Name: recordName,
			Type: "Microsoft.Network/dnszones/TXT",
			Etag: fmt.Sprintf("etag-%d", time.Now().Unix()),
			Properties: DNSTXTRecordProps{
				TTL:        req.Properties.TTL,
				Fqdn:       fmt.Sprintf("%s.%s.", recordName, zoneName),
				TXTRecords: req.Properties.TXTRecords,
			},
		}

		s.store.mu.Lock()
		s.store.dnsTXTRecords[resourceID] = record
		s.store.mu.Unlock()

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(record)

	case http.MethodGet:
		s.store.mu.RLock()
		record, exists := s.store.dnsTXTRecords[resourceID]
		s.store.mu.RUnlock()
		if !exists {
			s.resourceNotFound(w, "DNS TXT Record", recordName)
			return
		}
		json.NewEncoder(w).Encode(record)

	case http.MethodDelete:
		s.store.mu.Lock()
		delete(s.store.dnsTXTRecords, resourceID)
		s.store.mu.Unlock()
		w.WriteHeader(http.StatusOK)

	default:
		s.methodNotAllowed(w)
	}
}
```

Update the file header comment (lines 5-7) to list `Azure Front Door Standard/Premium (endpoints, routes, origin groups, origins, rule sets, rules, custom domains, purge)` and `Azure DNS (zones, CNAME and TXT records)`.

- [ ] **Step 7: Run the Go tests**

Run: `cd testing/docker/azure-mock && gofmt -l . && go vet ./... && go test ./...`
Expected: `gofmt -l` prints nothing, `go test` PASS.

- [ ] **Step 8: Build the mock image**

Run: `cd testing/docker && docker compose -f docker-compose.integration.yml build azure-mock`
Expected: image builds.

- [ ] **Step 9: Commit in the submodule and open its PR**

```bash
cd testing
git add docker/azure-mock/main.go docker/azure-mock/main_test.go
git commit -m "feat(azure-mock): emulate Front Door Standard/Premium resources, purge and DNS TXT records"
git push -u origin feat/azure-front-door-mock
gh pr create --title "feat(azure-mock): Front Door resources, purge and DNS TXT records" --body "Needed by nullplatform/scopes-static-files for the front-door distribution layer. Adds generic ARM handlers for afdEndpoints, routes, originGroups, origins, ruleSets, rules and profile-level customDomains, a purge action recorded at GET /mock/afd/purges, DNS TXT records, and frontDoorId on profiles."
```

Ask the user before `git push` and `gh pr create` (repo rule).

- [ ] **Step 10: Point the parent repo at the new submodule commit**

```bash
cd /Users/agustincelentano/repositories/scopes-static-files
git add testing
git commit -m "chore(testing): bump scope-testing to the Front Door mock"
```

The parent's integration suite checks the submodule out at that commit even before the submodule PR merges; re-bump to the merge commit once it lands.

---

### Task 9: Integration test case `azure_frontdoor_azuredns`

**Files:**
- Create: `static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/lifecycle_test.bats`
- Create: `static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/front_door_assertions.bash`
- Create: `static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/dns_assertions.bash` (copied from the blob-cdn case, edited)
- Delete: `static-files/deployment/tests/integration/test_cases/azure_blobcdn_azuredns/`

**Interfaces:**
- Consumes: `integration_setup --cloud-provider azure`, `azure_mock`, `azure_mock_put`, `azure_mock_delete`, `run_workflow`, `load_context`, `mock_request`, `clear_mocks` from `testing/integration_helpers.sh`; `assert_*` from `testing/assertions.sh`; mock endpoints from Task 8; env fallbacks from Task 3.
- Produces: `assert_azure_front_door_route_configured`, `assert_azure_front_door_route_not_configured`, `assert_azure_front_door_shared_resources_exist`, `assert_azure_front_door_purged`.

- [ ] **Step 1: Move the DNS assertions and delete the old case**

```bash
mkdir -p static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns
git mv static-files/deployment/tests/integration/test_cases/azure_blobcdn_azuredns/dns_assertions.bash static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/dns_assertions.bash
git rm -r static-files/deployment/tests/integration/test_cases/azure_blobcdn_azuredns
```

In the moved `dns_assertions.bash`, replace the two lines

```bash
  # The CNAME should point to the Azure CDN endpoint (azureedge.net)
  assert_contains "$cname_target" "azureedge.net"
```

with

```bash
  # The CNAME should point to the shared Front Door endpoint (azurefd.net)
  assert_contains "$cname_target" "azurefd.net"
```

and update its header comment to say Front Door.

- [ ] **Step 2: Write the Front Door assertions**

`front_door_assertions.bash`:

```bash
#!/bin/bash
# =============================================================================
# Azure Front Door Assertion Functions
#
# Validates the resources the front-door distribution layer creates inside a
# shared profile/endpoint, using the Azure Mock API server.
#
# Usage:
#   source "front_door_assertions.bash"
#   assert_azure_front_door_route_configured "app-name" "profile" "endpoint" "sub" "rg" "/origin/path" "full.domain"
# =============================================================================

_afd_profile_path() {
  echo "/subscriptions/$1/resourceGroups/$2/providers/Microsoft.Cdn/profiles/$3"
}

# +----------------------------------+----------------------------------------+
# | Assertion                        | Expected Value                         |
# +----------------------------------+----------------------------------------+
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
  local origin_path="$6" full_domain="$7" storage_account="$8" zone_name="$9" subdomain="${10}"

  local base
  base=$(_afd_profile_path "$subscription_id" "$resource_group" "$profile")

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

assert_azure_front_door_route_not_configured() {
  local app_name="$1" profile="$2" endpoint="$3" subscription_id="$4" resource_group="$5"
  local base
  base=$(_afd_profile_path "$subscription_id" "$resource_group" "$profile")

  assert_equal "$(azure_mock "${base}/afdEndpoints/${endpoint}/routes/${app_name}" | jq -r '.id // empty')" ""
  assert_equal "$(azure_mock "${base}/originGroups/${app_name}-og" | jq -r '.id // empty')" ""
  assert_equal "$(azure_mock "${base}/customDomains/${app_name}-domain" | jq -r '.id // empty')" ""
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
```

- [ ] **Step 3: Write the lifecycle test**

`lifecycle_test.bats`:

```bash
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

  # The zone lives in its own resource group (Task 2): setup preflight, data
  # source, CNAME and TXT all read and write it there.
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
```

Note `assert_azure_dns_configured` and `assert_azure_dns_not_configured` receive `TEST_DNS_ZONE_RESOURCE_GROUP` now: after Task 2 the CNAME lives in the zone's resource group. `context_azure.json` has no `scope-configurations` provider; `azure_dns/setup` falls back to `providers["cloud-providers"].networking.public_dns_zone_resource_group_name`, which is already `dns-resource-group` there. The zone is seeded in both resource groups only because the setup preflight reads it in `dns-resource-group` while the old module read it in `test-resource-group`; that is why `seed_shared_resources` creates the zone only under `TEST_DNS_ZONE_RESOURCE_GROUP`.

- [ ] **Step 4: Run the integration suite**

Run: `make test-integration MODULE=static-files VERBOSE=1`
Expected: both Azure tests PASS alongside the AWS case. Typical first failures and their causes:
- `az rest` fails to authenticate inside the runner: `_configure_azure_cli` did not run; check `testing/integration_helpers.sh` `_setup_azure`.
- purge 404: the endpoint key casing differs; the mock lower-cases keys, the purge handler must too (it does via `strings.ToLower`).
- data source `azurerm_cdn_frontdoor_profile` errors on `frontDoorId`: Task 8 Step 4 missed `FrontDoorID`.

- [ ] **Step 5: Commit**

```bash
git add -A static-files/deployment/tests/integration static-files/deployment/tests/resources/context_azure.json
git commit -m "test(integration): cover the front-door layer against the Azure mock"
```

---

### Task 10: Real end-to-end run and release notes

**Files:**
- Modify: `docs/design/azure-front-door.md` (Status line)
- No code changes expected; fixes found here get their own commits in the task they belong to.

**Interfaces:**
- Consumes: an Azure subscription with a resource group, a DNS zone delegated from a public domain, a storage account with static website enabled and a bundle uploaded at `frontends/<app>/<build>`, a Front Door Standard profile and endpoint, an agent identity with the roles from Task 6's label, and a nullplatform organization where `static-files/specs/install/azure` was applied.

- [ ] **Step 1: Install the scope with the reference example**

```bash
cp -r static-files/specs/install/azure /tmp/sf-azure && cd /tmp/sf-azure
cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars
tofu init && tofu apply
```
Expected: scope definition, provider config with `azure_distribution = "front-door"` and the profile/endpoint names registered.

- [ ] **Step 2: Register an asset from a CI-like shell**

Run the two commands from `docs/design/azure-front-door.md` ("Asset publishing") against the real storage account.
Expected: `np asset create` returns an asset whose `url` starts with `https://<account>.blob.core.windows.net/$web/`.

- [ ] **Step 3: Create a scope and deploy**

Create a scope of type Static Files and start an initial deployment through the UI (`https://<org-slug>.app.nullplatform.io/...` link of the application). Watch the workflow logs.
Expected checklist, in order:
1. `front-door/setup` prints `✅ endpoint_host=<endpoint>-<hash>.z01.azurefd.net`.
2. `tofu apply` creates origin group, origin, rule set, two rules, route, custom domain, TXT record, association.
3. Purge succeeds while the domain is still `Pending` (Review Focus 5). If Azure rejects it, change `terraform_data.front_door_purge` in Task 5 to tolerate HTTP 400 with `DomainNotFound` only, document it, and re-run.
4. Within ~10 minutes `https://<app>-<scope>.<zone>` serves `index.html` with a valid certificate and a client-side route (`/some/path`) also returns `index.html`.
5. Deep links and the home page serve the deployed version, not `$web/index.html` from the container root: request `/` and `/some/client/route` and compare with the bundle at the current origin path. If Front Door's URL rewrite bypasses the route's origin path, prefix `destination` in `azurerm_cdn_frontdoor_rule.spa_fallback` with `local.distribution_origin_path`.
6. After the second deploy (Step 4), repeat the request to `/` and to a deep link every minute for ten minutes: no stale content. If stale content appears, add a rule that disables caching for `text/html` (or everything outside `/static/`) so the purge is not the only invalidation mechanism.

- [ ] **Step 4: Deploy a second build and confirm the version switch**

Register a second asset with a different `build_id`, deploy it.
Expected: the route's origin path changes, a purge is issued, the new bundle is served within a minute. `az afd route show` confirms `originPath`.

- [ ] **Step 5: Delete the scope**

Delete the scope through the UI.
Expected: route, origin group, origin, rule set, custom domain, TXT and CNAME are gone; profile and endpoint remain; `az afd endpoint list` still shows the endpoint.

- [ ] **Step 6: Record the result**

In `docs/design/azure-front-door.md` change the Status line to `Status: implemented and verified end to end on <date> (subscription <name>).` and add a "Verified behaviors" list with the outcome of Step 3 item 3.

- [ ] **Step 7: Commit and open the PR**

```bash
git add docs/design/azure-front-door.md
git commit -m "docs(design): record the Front Door end-to-end verification"
git push -u origin feat/azure-front-door
gh pr create --title "feat(distribution)!: Azure Front Door distribution, remove Azure CDN classic" --body-file docs/plans/2026-09-29-azure-front-door.md
```

Ask the user before `git push` and `gh pr create`. The `!` makes release-please cut a major version, which is what removing `blob-cdn` deserves.
