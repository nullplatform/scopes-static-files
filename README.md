# Static Files Deployment Module

This module provides infrastructure-as-code for deploying static files applications across multiple cloud providers. It uses a **layered architecture** that separates concerns and enables mix-and-match combinations of providers, DNS solutions, and CDN/hosting platforms.

## Table of Contents

- [Install in your organization](#install-in-your-organization)
- [Architecture Overview](#architecture-overview)
- [Layer System](#layer-system)
- [Variable Naming Conventions](#variable-naming-conventions)
- [Cross-Layer Communication](#cross-layer-communication)
- [Adding New Layer Implementations](#adding-new-layer-implementations)
- [Setup Script Patterns](#setup-script-patterns)
- [Run Locally as a Package](#run-locally-as-a-package)
- [Testing](#testing)
- [Quick Reference](#quick-reference)

---

## Install in your organization

The scope is published once as the package `np-static-files` (scope type "Static files"), visible to every organization. You do not copy its specs: you install the package and use it read-only.

How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to this scope.

Already registered a copy with tofu-modules' `scope_definition` (the former `static-files/specs/install/` examples)? It keeps working: it registered specs that stay in every release, and the package installs next to it, as the guide explains. If you sourced that directory as a module, pin its `?ref` to a release that still has it.

Installing it touches the same three layers as registering a scope yourself, and only the nullplatform layer changes:

| Layer | What | Module |
|---|---|---|
| infrastructure (cloud credentials) | On AWS, the permissions role the agent assumes; on Azure, the Front Door profile, the optional WAF policy and the role assignments of the agent identity | [`static-files/specs/requirements/aws`](./static-files/specs/requirements/aws), [`static-files/specs/requirements/azure`](./static-files/specs/requirements/azure) |
| nullplatform (nullplatform API key) | The installation of the package, the scope type, the NRN settings and the scope-configuration schema | tofu-modules' `scope_package_installation` |
| bindings | The agent channel, the role under selector `static-files` in your IAM provider, and the scope's settings | tofu-modules' `scope_definition_agent_association`, your providers |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/scopes-static-files/releases)) and use its version in every place below: the IAM role is the one the worker of that same release expects.

```hcl
# ── infrastructure layer ─────────────────────────────────────────────
# AWS: the role the worker assumes (its README lists every input).
module "static_files_requirements" {
  source = "git::https://github.com/nullplatform/scopes-static-files.git//static-files/specs/requirements/aws?ref=vX.Y.Z"

  cluster_name      = "my-cluster" # names the role nullplatform_my-cluster_static_scopes_role
  agent_role_arn    = module.agent_iam.nullplatform_agent_role_arn
  assets_bucket_arn = aws_s3_bucket.frontends.arn # emits the OAC bucket policy statement to merge
}

# The agent role must be allowed to assume it: add it to the assume_role_arns
# of tofu-modules' infrastructure/aws/iam/agent.
#   assume_role_arns = [..., module.static_files_requirements.permissions_role_arn]
#
# Azure: static-files/specs/requirements/azure instead (Front Door, WAF, role
# assignments); its outputs feed the scope settings below.

# ── nullplatform layer ───────────────────────────────────────────────
module "static_files" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_package_installation?ref=v9.16.0"

  nrn             = var.nrn
  np_api_key      = var.np_api_key # for the NRN settings patch (np nrn patch)
  package_slug    = "np-static-files"
  package_version = "X.Y.Z" # the same release, without the v

  # Yours, created from this repository's templates at the same release:
  service_spec_name                = "Static files" # the scope type developers pick
  service_spec_description         = "Allows you to deploy static files applications"
  service_path                     = "static-files"
  repository_scope_template        = "https://raw.githubusercontent.com/nullplatform/scopes-static-files/refs/tags"
  repository_scope_template_branch = "vX.Y.Z" # the same release
  create_scope_configuration       = true
  create_agent_channel             = false # the channel lives in your bindings layer, below
}

# ── bindings layer ───────────────────────────────────────────────────
# static_files_requirements and static_files come from the other layers (remote state).
module "static_files_channel" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v9.16.0"

  nrn                      = var.nrn
  tags_selectors           = { cluster = "runtime" } # must match the agent's TAGS
  scope_specification_id   = local.static_files.service_specification_id
  scope_specification_slug = local.static_files.service_specification_slug
  service_path             = "static-files"

  # The channel template, from the same tag
  repository_notification_channel        = "https://raw.githubusercontent.com/nullplatform/scopes-static-files/refs/tags"
  repository_notification_channel_branch = "vX.Y.Z" # the same release

  worker_orchestrator = true
  package_slug        = local.static_files.package_slug
}

# The scope's settings, in a provider of the schema the installation created:
# one per NRN (typically one per environment or region). cloud_provider picks
# the layers; the keys of every layer and cloud are in
# static-files/specs/scope-configuration.json.tpl. AWS shown; on Azure the
# provider, network and distribution blocks take the azure_* keys and the
# values come from the requirements/azure outputs.
resource "nullplatform_provider_config" "static_files_configuration" {
  nrn  = var.nrn
  type = local.static_files.scope_configuration_specification_slug
  attributes = jsonencode({
    cloud_provider = "aws"
    provider       = { aws_region = "us-east-1", aws_state_bucket = "my-tofu-state-bucket" }
    network        = { aws_network = "route53", aws_hosted_public_zone_id = "Z0100000000000000000A" }
    distribution   = { aws_distribution = "cloudfront" }
  })
}

# One aws-iam-configuration per NRN and dimensions: add the entry to the list
# your IAM provider already has.
#   { selector = "static-files", arn = local.static_files_requirements.permissions_role_arn }
```

The scope assumes the role it finds under selector `static-files` in the IAM provider closest to its NRN. To upgrade, move the release in every layer: `ref` of the requirements module, `package_version` and `repository_scope_template_branch` of the installation and `repository_notification_channel_branch` of the channel. See tofu-modules' [`scope_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/scope_package_installation) for its inputs and outputs.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors`, with `np-static-files` in its `worker_orchestrated_packages` and `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries`, and the cloud resources of the scope README's [Pre-requisites](./static-files/README.md#pre-requisites) (state bucket, hosted zone, certificate, assets bucket).

Every release publishes the new revision from this repository ([`static-files/publish`](./static-files/publish), a stack on tofu-modules' `scope_package_publish`, applied by the `publish-package` job of the release workflow).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        WORKFLOW ENGINE                          │
│  (workflows/initial.yaml, workflows/delete.yaml)                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      LAYER COMPOSITION                          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   PROVIDER   │  │   NETWORK    │  │    DISTRIBUTION      │  │
│  │    LAYER     │──▶    LAYER     │──▶       LAYER          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                 │
│  Implementations:   Implementations:   Implementations:         │
│  • aws              • route53          • cloudfront             │
│  • azure            • azure_dns        • front-door             │
│  • gcp              • cloud_dns        • amplify                │
│                                        • firebase               │
│                                        • gcs-cdn                │
│                                        • static-web-apps        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TERRAFORM/OPENTOFU                          │
│  (composed modules from all active layers)                      │
└─────────────────────────────────────────────────────────────────┘
```

### Layer Flow

1. **Provider Layer**: Configures cloud credentials, state backend, and resource tags
2. **Network Layer**: Sets up DNS zones and records, calculates domains
3. **Distribution Layer**: Deploys CDN/hosting with references to network outputs

---

## Layer System

Each layer consists of two components:

### 1. Setup Script (`setup`)

A bash script that:
- Validates required inputs (environment variables, context)
- Fetches external data (cloud APIs, nullplatform API)
- Updates `TOFU_VARIABLES` with layer-specific configuration
- Registers the module directory in `MODULES_TO_USE`

### 2. Modules Directory (`modules/`)

Terraform/OpenTofu files:
- `main.tf` - Resource definitions
- `variables.tf` - Input variable declarations
- `locals.tf` - Computed values and cross-layer references
- `outputs.tf` - Exported values for other layers
- `test_locals.tf` - Test-only stubs (skipped during composition)

### Directory Structure

```
static-files/deployment/
├── provider/
│   └── {cloud}/
│       ├── setup              # Validation & module registration
│       └── modules/
│           ├── provider.tf    # Backend & provider config
│           └── variables.tf
│
├── network/
│   └── {dns_provider}/
│       ├── setup
│       └── modules/
│           ├── main.tf
│           ├── variables.tf
│           ├── locals.tf
│           ├── outputs.tf
│           └── test_locals.tf
│
├── distribution/
│   └── {cdn_provider}/
│       ├── setup
│       └── modules/
│           ├── main.tf
│           ├── variables.tf
│           ├── locals.tf
│           ├── outputs.tf
│           └── test_locals.tf
│
├── scripts/                   # Shared helper scripts
├── workflows/                 # Workflow definitions
└── tests/                     # Unit and integration tests
```

---

## Variable Naming Conventions

**All variables MUST use layer-prefixed naming** for clarity and to avoid conflicts:

| Layer | Prefix | Examples |
|-------|--------|----------|
| **Provider** | `{cloud}_provider` | `azure_provider`, `aws_provider`, `gcp_provider` |
| **Provider** | `provider_*` | `provider_resource_tags_json` |
| **Network** | `network_*` | `network_domain`, `network_subdomain`, `network_full_domain`, `network_dns_zone_name` |
| **Distribution** | `distribution_*` | `distribution_storage_account`, `distribution_app_name`, `distribution_blob_prefix` |

### Provider Object Structure

Each cloud provider uses an object variable:

```hcl
# Azure
variable "azure_provider" {
  type = object({
    subscription_id = string
    resource_group  = string
    storage_account = string  # For Terraform state
    container       = string  # For Terraform state
  })
}

# AWS
variable "aws_provider" {
  type = object({
    region       = string
    state_bucket = string
  })
}

# GCP
variable "gcp_provider" {
  type = object({
    project = string
    region  = string
    bucket  = string
  })
}
```

### Cross-Layer Shared Variables

These variables are used by multiple layers and MUST use consistent naming across implementations:

| Variable | Set By | Used By | Description |
|----------|--------|---------|-------------|
| `network_full_domain` | Network | Distribution | Full domain (e.g., `app.example.com`) |
| `network_domain` | Network | Distribution | Base domain (e.g., `example.com`) |
| `network_subdomain` | Network | Distribution | Subdomain part (e.g., `app`) |
| `distribution_target_domain` | Distribution | Network | CDN endpoint hostname for DNS record |
| `distribution_record_type` | Distribution | Network | DNS record type (`CNAME` or `A`) |

---

## Cross-Layer Communication

Layers communicate through **locals** that are merged when modules are composed together.

### How It Works

1. Each layer defines locals in `locals.tf`
2. When modules are composed, all locals are merged into a single namespace
3. Layers can reference each other's locals directly

### Example: Network → Distribution

**Network layer exports** (`network/azure_dns/modules/locals.tf`):
```hcl
locals {
  network_full_domain = "${var.network_subdomain}.${var.network_domain}"
  network_domain      = var.network_domain
}
```

**Distribution layer consumes** (`distribution/front-door/modules/locals.tf`):
```hcl
locals {
  # References network layer's local directly
  distribution_has_custom_domain = local.network_full_domain != ""
  distribution_full_domain       = local.network_full_domain
}
```

### Test Locals (`test_locals.tf`)

For unit testing modules in isolation, use `test_locals.tf` to stub cross-layer dependencies:

```hcl
# File: test_locals.tf
# NOTE: Files matching test_*.tf are skipped by compose_modules

variable "network_full_domain" {
  description = "Test-only: Simulates network layer output"
  default     = ""
}

locals {
  network_full_domain = var.network_full_domain
}
```

---

## Adding New Layer Implementations

### Quick Start with Boilerplate Script

Use the provided script to generate the folder structure:

```bash
# Create a new network layer implementation
./scripts/setup-layer --type network --name cloudflare

# Create a new distribution layer implementation
./scripts/setup-layer --type distribution --name netlify

# Create a new provider layer implementation
./scripts/setup-layer --type provider --name digitalocean
```

This creates:
```
static-files/deployment/{type}/{name}/
├── setup                    # Boilerplate setup script
└── modules/
    ├── main.tf              # Empty, ready for resources
    ├── variables.tf         # Layer-prefixed variables
    ├── locals.tf            # Cross-layer locals
    ├── outputs.tf           # Layer outputs
    └── test_locals.tf       # Test stubs
```

### Manual Steps After Generation

1. **Edit `setup` script**: Add validation logic and TOFU_VARIABLES updates
2. **Edit `modules/main.tf`**: Add Terraform resources
3. **Edit `modules/variables.tf`**: Define required inputs
4. **Update `modules/locals.tf`**: Add cross-layer references
5. **Add tests**: Create `tests/{type}/{name}/` with `.tftest.hcl` files

---

## Setup Script Patterns

### Required Structure

Every setup script must:

```bash
#!/bin/bash
# =============================================================================
# {Layer Type}: {Implementation Name}
#
# Brief description of what this layer does.
# =============================================================================

set -euo pipefail

# 1. VALIDATION PHASE
echo "🔍 Validating {Implementation} configuration..."
echo ""

# Validate required variables
if [ -z "${REQUIRED_VAR:-}" ]; then
  echo "   ❌ REQUIRED_VAR is missing"
  echo ""
  echo "  💡 Possible causes:"
  echo "    • Variable not set in environment"
  echo ""
  echo "  🔧 How to fix:"
  echo "    • Set REQUIRED_VAR in your environment"
  exit 1
fi
echo "   ✅ REQUIRED_VAR=$REQUIRED_VAR"

# 2. EXTERNAL DATA FETCHING (if needed)
echo ""
echo "   📡 Fetching {resource}..."
# Call APIs, validate responses

# 3. UPDATE TOFU_VARIABLES
TOFU_VARIABLES=$(echo "$TOFU_VARIABLES" | jq \
  --arg var_name "$var_value" \
  '. + {
    layer_variable_name: $var_name
  }')

# 4. REGISTER MODULE
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
module_name="${script_dir}/modules"

if [[ -n ${MODULES_TO_USE:-} ]]; then
  MODULES_TO_USE="$MODULES_TO_USE,$module_name"
else
  MODULES_TO_USE="$module_name"
fi

echo ""
echo "✨ {Implementation} configured successfully"
echo ""
```

### Logging Conventions

| Icon | Usage |
|------|-------|
| `🔍` | Starting validation phase |
| `✅` | Successful validation |
| `❌` | Failed validation |
| `📡` | Fetching external data |
| `📝` | Performing an action |
| `💡` | Possible causes of error |
| `🔧` | How to fix instructions |
| `📋` | Debug information |
| `✨` | Success summary |

### Error Handling Pattern

```bash
if [ $? -ne 0 ]; then
  echo "   ❌ Failed to {action}"
  echo ""

  # Classify error type
  if echo "$output" | grep -q "NotFound"; then
    echo "  🔎 Error: Resource not found"
  elif echo "$output" | grep -q "Forbidden\|403"; then
    echo "  🔒 Error: Permission denied"
  else
    echo "  ⚠️  Error: Unknown error"
  fi

  echo ""
  echo "  💡 Possible causes:"
  echo "    • Cause 1"
  echo "    • Cause 2"
  echo ""
  echo "  🔧 How to fix:"
  echo "    1. Step 1"
  echo "    2. Step 2"
  echo ""
  echo "  📋 Error details:"
  echo "$output" | sed 's/^/    /'

  exit 1
fi
```

---

## Run Locally as a Package

You can run this scope on your machine the way production runs it: a dockerized
nullplatform agent registers with the platform, spawns this scope's worker
container, and hands it each action over gRPC. The bash scripts are not changed
for this. The worker image is built `FROM` the `worker-bridge` base (see the
`Dockerfile`), which receives the action and runs `entrypoint` exactly as the
classic agent did.

This repo is a **base package**: it has no `package.json` and no manifest. The
two tasks in `mise.toml` are the whole contract with the CLI.

| Command | Runs | Does |
|---------|------|------|
| `np package build --image` | `mise run build:image` | Builds `scopes-static-files-worker:dev` |
| `np package run` | `mise run run` | Builds the image, then starts the local agent |

### Prerequisites

- **Docker**, with host networking. On Linux it works as is; on Docker Desktop
  enable *host networking* in the settings.
- **[mise](https://mise.jdx.dev)**. Run `mise trust` once in this directory.
- **`NP_API_KEY`**: an API key the agent registers with.
- **`np` from the alpha channel** — it carries `np package run`
  ([nullplatform/cli#243](https://github.com/nullplatform/cli/pull/243), not on
  `latest` yet):

  ```bash
  curl -fsSL https://cli.nullplatform.com/install.sh | VERSION=alpha sh   # installs to ~/.local/bin/np
  np package run --help                                                   # must list --no-forward-env
  ```

  Without it, `mise run run` starts the same agent but forwards nothing.

### Run it

```bash
export NP_API_KEY=...

np package run --log-level DEBUG     # Ctrl+C to stop
# or, without the CLI:
mise run run
```

The agent is tagged `package:scopes-static-files` and `local:<your user>`. It
receives an action only when the scope's notification channel selects those
tags, so point a channel at `local:<your user>` to route work to your machine.

> **Tags decide who gets the work.** Never start a local agent with tags a
> production channel selects: it would receive production actions.

### Settings

| Variable | Default | Purpose |
|----------|---------|---------|
| `NP_API_KEY` | required | The key the agent registers with. `np package run --api-key` also sets it. |
| `NP_LOG_LEVEL` | `INFO` | Agent log level. `np package run --log-level` also sets it. |
| `NP_PACKAGE_SLUG` | `scopes-static-files` | The slug in the `package:<slug>` tag. Set it when your package is published under another slug. |
| `NP_LOCAL_USER` | `$USER` | The value of the `local:<user>` tag. `np package run` sets it. |
| `NP_AGENT_IMAGE` | `controlplane-agent:latest` | The agent image to run. Needs worker rules (0.11.1+). |
| `STATIC_FILES_ASSUME_ROLE_ARN` | resolved from the IAM provider | `none` = keep the credentials you exported instead of assuming the cluster role (local runs) |
| `NP_PACKAGE_ENV_FLAGS` | empty | Set by `np package run`: the shell variables to forward, as `-e NAME` flags (agent container). |
| `NP_PACKAGE_ENV_JSON` | empty | Set by `np package run`: the same variables as JSON, handed to the worker through `NP_WORKER_RULES`. |

### Cloud credentials and your environment

`np package run` forwards your shell's environment to the agent container. It
holds back variables that describe your machine rather than the work: `PATH`,
`HOME`, `DOCKER_*`, `KUBECONFIG`, and the AWS variables that point at files the
container does not have (`AWS_PROFILE`, `AWS_CONFIG_FILE`,
`AWS_SHARED_CREDENTIALS_FILE`). So export credentials as variables:

```bash
eval "$(aws configure export-credentials --format env)"
np package run
```

Pass `--no-forward-env` to forward nothing. Every secret in your shell is
forwarded otherwise, and is readable with `docker inspect` on your machine.

> **How the variables reach the worker.** The `-e` flags put them in the
> **agent** container. The agent gives a **worker** only the env it is
> configured with, so the `run` task also passes an `NP_WORKER_RULES` entry
> built from `NP_PACKAGE_ENV_JSON` (`{"match":{"package":"scopes-static-files"},"env":{…}}`),
> and the agent injects that env into the worker it spawns for this package.
> Worker rules exist in `controlplane-agent` 0.11.1 and newer; `latest` (the
> default) has them, the old `alpha-packages-*` tags do not.

### When it works: publish it

The local run never changes what the platform runs. To ship the change:

1. Push the image and register it as an artifact revision — CI does it on a
   release tag (`release.yml`), or from any branch with the `test-image` workflow
   (Actions → test-image → Run workflow), whose summary prints the artifact and
   revision ids.
2. Publish a package version that pins it: `PUT /packages` with `bump: patch`
   and the `worker-image` component set to that artifact revision (and the
   `scope` component to the spec's newest snapshot when the spec changed).
   `merge_components` keeps every other component of the latest BOM.
3. New scopes bind to the package **default**; existing ones move through a
   rollout. The exact calls, run live, are in the `np-package-builder` skill
   (`docs/local-loop.md`, *After it works*).

### Troubleshooting a local run

| Issue | Cause | Solution |
|-------|-------|----------|
| `set NP_API_KEY` | No API key in the environment | `export NP_API_KEY=...`, or pass `--api-key` |
| "doesn't look like a package" | An `np` without base package support (`latest`) | Install the alpha channel (see Prerequisites), or run `mise run run` |
| `mise` refuses to run the tasks | The config is not trusted yet | `mise trust` |
| The agent starts but never reaches the worker | No host networking | Enable host networking in Docker Desktop |
| The agent is up but no action arrives | No channel selects your tags | Add a channel selector for `local:<your user>` |
| `sts:AssumeRole … AccessDenied` for **your** identity | The scope assumes the role from the account's IAM provider, whose trust policy trusts only the cluster's agent role | `export STATIC_FILES_ASSUME_ROLE_ARN=none` to run with the credentials you exported (forwarded like any variable), or set it to a role you can assume |

---

## Testing

This module uses the testing framework defined in the [scope-testing](https://github.com/nullplatform/scope-testing) repository, which is included as a Git submodule. To initialize the submodule, run the following commands:

```bash
git submodule add git@github.com:nullplatform/scope-testing.git testing
git submodule init && git submodule update
```

We use **three types of tests** to ensure quality at different levels:

| Test Type | What it Tests | Location | Command |
|-----------|---------------|----------|---------|
| **Unit Tests (BATS)** | Bash setup scripts | `tests/{layer_type}/{name}/` | `make test-unit` |
| **Tofu Tests** | Terraform modules | `{layer_type}/{name}/modules/*.tftest.hcl` | `make test-tofu` |
| **Integration Tests** | Full workflow execution | `tests/integration/test_cases/` | `make test-integration` |

### 1. Unit Tests (BATS)

Test bash setup scripts in isolation using mocked commands.

**Location:** `static-files/deployment/tests/{layer_type}/{name}/setup_test.bats`

**Run:** `make test-unit` or `make test-unit MODULE=static-files`

**Example files:**
- Provider: [`tests/provider/azure/setup_test.bats`](deployment/tests/provider/azure/setup_test.bats)
- Network: [`tests/network/azure_dns/setup_test.bats`](deployment/tests/network/azure_dns/setup_test.bats)
- Distribution: [`tests/distribution/front-door/setup_test.bats`](deployment/tests/distribution/front-door/setup_test.bats)

**Structure:**
```bash
#!/usr/bin/env bats

setup() {
  # Mock external commands (jq, az, aws, np, etc.)
  # Set required environment variables
  export CONTEXT='{"key": "value"}'
  export TOFU_VARIABLES='{}'
}

@test "validates required environment variable" {
  unset REQUIRED_VAR
  run source_setup
  assert_failure
  assert_output --partial "REQUIRED_VAR is missing"
}

@test "sets TOFU_VARIABLES correctly" {
  export REQUIRED_VAR="test-value"
  run source_setup
  assert_success
  # Check TOFU_VARIABLES was updated correctly
}
```

### 2. Tofu Tests (OpenTofu/Terraform)

Test Terraform modules using `tofu test` with mock providers.

**Location:** `static-files/deployment/{layer_type}/{name}/modules/{name}.tftest.hcl`

**Run:** `make test-tofu` or `make test-tofu MODULE=static-files`

**Example files:**
- Provider: [`provider/azure/modules/provider.tftest.hcl`](deployment/provider/azure/modules/provider.tftest.hcl)
- Network: [`network/azure_dns/modules/azure_dns.tftest.hcl`](deployment/network/azure_dns/modules/azure_dns.tftest.hcl)
- Distribution: [`distribution/front-door/modules/front-door.tftest.hcl`](deployment/distribution/front-door/modules/front-door.tftest.hcl)

**Structure:**
```hcl
# =============================================================================
# Mock Providers
# =============================================================================
mock_provider "azurerm" {}

# =============================================================================
# Test Variables
# =============================================================================
variables {
  network_domain    = "example.com"
  network_subdomain = "app"
}

# =============================================================================
# Tests
# =============================================================================
run "test_dns_record_created" {
  command = plan

  assert {
    condition     = azurerm_dns_cname_record.main[0].name == "app"
    error_message = "CNAME record name should be 'app'"
  }
}

run "test_full_domain_output" {
  command = plan

  assert {
    condition     = output.network_full_domain == "app.example.com"
    error_message = "Full domain should be 'app.example.com'"
  }
}
```

### 3. Integration Tests (BATS)

Test complete workflows with mocked external dependencies (LocalStack, Azure Mock, Smocker).

**Location:** `static-files/deployment/tests/integration/test_cases/{scenario}/lifecycle_test.bats`

**Run:** `make test-integration` or `make test-integration MODULE=static-files`

**Example file:** [`tests/integration/test_cases/azure_frontdoor_azuredns/lifecycle_test.bats`](deployment/tests/integration/test_cases/azure_frontdoor_azuredns/lifecycle_test.bats)

**What's mocked:**
- **LocalStack**: AWS services (S3, Route53, STS, IAM, ACM)
- **Moto**: CloudFront (not in LocalStack free tier)
- **Azure Mock**: Azure ARM APIs (Front Door, DNS, Storage) + Blob Storage
- **Smocker**: nullplatform API

**Structure:**
```bash
#!/usr/bin/env bats

# Test constants derived from context
TEST_DISTRIBUTION_APP_NAME="my-app"
TEST_NETWORK_DOMAIN="example.com"

setup_file() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  integration_setup --cloud-provider azure  # or: aws
  # Pre-create required resources in mocks
}

teardown_file() {
  integration_teardown
}

setup() {
  source "${PROJECT_ROOT}/testing/integration_helpers.sh"
  load_context "static-files/deployment/tests/resources/context.json"

  # Configure layer selection
  export NETWORK_LAYER="azure_dns"
  export DISTRIBUTION_LAYER="front-door"
  export TOFU_PROVIDER="azure"

  # Setup API mocks
  mock_request "GET" "/provider" "mocks/provider.json"
}

@test "create infrastructure deploys resources" {
  run_workflow "static-files/deployment/workflows/initial.yaml"

  assert_azure_front_door_route_configured "$TEST_DISTRIBUTION_APP_NAME" ...
  assert_azure_dns_configured "$TEST_NETWORK_DOMAIN" ...
}

@test "destroy infrastructure removes resources" {
  run_workflow "static-files/deployment/workflows/delete.yaml"

  assert_azure_front_door_route_not_configured ...
  assert_azure_dns_not_configured ...
}
```

### Running Tests

```bash
# Run all tests
make test-all

# Run specific test types
make test-unit              # BATS unit tests for bash scripts
make test-tofu              # OpenTofu module tests
make test-integration       # Full workflow integration tests

# Run tests for specific module
make test-unit MODULE=static-files
make test-tofu MODULE=static-files
make test-integration MODULE=static-files

# Run with verbose output (integration only)
make test-integration VERBOSE=1
```

---

## Quick Reference

### Environment Variables by Provider

#### AWS
```bash
export TOFU_PROVIDER=aws
export AWS_REGION=us-east-1
export TOFU_PROVIDER_BUCKET=my-state-bucket
```

#### Azure
```bash
export TOFU_PROVIDER=azure
export AZURE_SUBSCRIPTION_ID=xxx
export AZURE_RESOURCE_GROUP=my-rg
export TOFU_PROVIDER_STORAGE_ACCOUNT=mystateaccount
export TOFU_PROVIDER_CONTAINER=tfstate
```

#### GCP
```bash
export TOFU_PROVIDER=gcp
export GOOGLE_PROJECT=my-project
export GOOGLE_REGION=us-central1
export TOFU_PROVIDER_BUCKET=my-state-bucket
```

### Layer Selection

```bash
export NETWORK_LAYER=route53        # or: azure_dns, cloud_dns
export DISTRIBUTION_LAYER=cloudfront # or: front-door
```

---

## AI Assistant Prompt for Implementing New Layers

When asking an AI assistant to help implement a new layer, just paste this prompt:

````
I need to implement a new layer in the static-files deployment module.

**IMPORTANT:** Before starting:

1. Read `static-files/README.md` to understand:
   - The layer system architecture and how layers interact
   - Variable naming conventions (layer prefixes)
   - Cross-layer communication via locals
   - Setup script patterns and logging conventions
   - Testing requirements (unit, tofu, integration)

2. Ask me for the following information:
   - Layer type (provider, network, or distribution)
   - Provider/service name (e.g., Cloudflare, Netlify, DigitalOcean)
   - Required environment variables or context values to validate
   - External APIs to call (if any)
   - Terraform resources to create
   - Cross-layer dependencies and exports

3. After gathering requirements, generate:
   - Setup script with validation and TOFU_VARIABLES
   - Terraform module (main.tf, variables.tf, locals.tf, outputs.tf, test_locals.tf)
   - Unit tests (BATS) for the setup script
   - Tofu tests for the Terraform module
   - Integration test additions (if applicable)

**Reference Files by Layer Type:**

For PROVIDER layers, reference:
- Setup script: `static-files/deployment/provider/azure/setup`
- Terraform module: `static-files/deployment/provider/azure/modules/`
- Unit test (BATS): `static-files/deployment/tests/provider/azure/setup_test.bats`
- Tofu test: `static-files/deployment/provider/azure/modules/provider.tftest.hcl`

For NETWORK layers, reference:
- Setup script: `static-files/deployment/network/azure_dns/setup`
- Terraform module: `static-files/deployment/network/azure_dns/modules/`
- Unit test (BATS): `static-files/deployment/tests/network/azure_dns/setup_test.bats`
- Tofu test: `static-files/deployment/network/azure_dns/modules/azure_dns.tftest.hcl`

For DISTRIBUTION layers, reference:
- Setup script: `static-files/deployment/distribution/front-door/setup`
- Terraform module: `static-files/deployment/distribution/front-door/modules/`
- Unit test (BATS): `static-files/deployment/tests/distribution/front-door/setup_test.bats`
- Tofu test: `static-files/deployment/distribution/front-door/modules/front-door.tftest.hcl`

For INTEGRATION tests, reference:
- `static-files/deployment/tests/integration/test_cases/azure_frontdoor_azuredns/lifecycle_test.bats`
````

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Variable not found" | Missing setup script execution | Ensure workflow runs all setup scripts in order |
| "Local not found" | Missing cross-layer local | Add to `locals.tf` or check `test_locals.tf` for unit tests |
| "Module not composed" | `MODULES_TO_USE` not updated | Verify setup script appends to `MODULES_TO_USE` |
| "Backend not configured" | Missing provider setup | Run provider layer setup first |

### Debug Commands

```bash
# Check composed modules
echo $MODULES_TO_USE

# Check TOFU_VARIABLES
echo $TOFU_VARIABLES | jq .

# Validate terraform
cd /path/to/composed/modules && tofu validate
```
