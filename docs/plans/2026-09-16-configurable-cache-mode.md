# Configurable Cache Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each CloudFront behavior choose between the legacy cache settings it uses today and the cache policy / origin request policy model, with legacy as the default.

**Architecture:** Three fields are added to the scope configuration — on the default behavior as flat `default_*` keys, and inside each item of `distribution.behaviors[]` unprefixed. `setup` folds the flat keys into the object the module already takes. In the module, `forwarded_values` and the TTLs become conditional on the mode, and two new data sources resolve managed policy names to ids.

**Tech Stack:** OpenTofu (AWS provider), JSON Schema + JSONForms uiSchema, bash + jq, BATS, `tofu test` (`.tftest.hcl`).

**Spec:** `docs/design/configurable-cache-mode.md`

## Global Constraints

- Legacy is the default everywhere. An unset `cache_mode` must produce a plan identical to today's.
- Managed policies only. `cache_policy` and `origin_request_policy` are closed enums; no ids, no custom policies.
- `forwarded_values` and `cache_policy_id` are mutually exclusive on a behavior, and `min_ttl` / `default_ttl` / `max_ttl` cannot be set alongside a cache policy.
- Legacy TTLs are exactly `min_ttl = 0`, `default_ttl = 3600`, `max_ttl = 86400`.
- The default behavior's schema keys carry the `default_` prefix; the keys inside `behaviors[]` do not.
- Cache policy enum: `CachingOptimized`, `CachingDisabled`, `CachingOptimizedForUncompressedObjects`, `Amplify`. Default `CachingOptimized`.
- Origin request policy enum: `AllViewerExceptHostHeader`, `AllViewer`, `CORS-S3Origin`, `CORS-CustomOrigin`, `UserAgentRefererHeaders`. Default `AllViewerExceptHostHeader`.
- These fields live under the AWS branch of the form only. Azure (`blob-cdn`) is untouched.
- Response headers policy enum: `""` (None, the default), `SecurityHeadersPolicy`, `CORS-and-SecurityHeadersPolicy`, `SimpleCORS`, `CORS-With-Preflight`, `CORS-with-preflight-and-SecurityHeadersPolicy`.
- `response_headers_policy` is NOT gated behind `cache_mode`. It is always visible and works in both modes — it is not mutually exclusive with `forwarded_values`.
- Array controls in the uiSchema carry `elementLabelProp` so each item is labelled by a field that identifies it, not by whatever the renderer picks.

---

### Task 1: Schema and uiSchema

**Files:**
- Modify: `static-files/specs/scope-configuration.json.tpl`

**Interfaces:**
- Consumes: nothing.
- Produces: the scope configuration keys `distribution.default_cache_mode`, `distribution.default_cache_policy`, `distribution.default_origin_request_policy`, and inside each `distribution.behaviors[]` item `cache_mode`, `cache_policy`, `origin_request_policy`. Every later task reads these names.

- [ ] **Step 1: Add the three fields to the default behavior**

In the `distribution` properties block, right after `default_invocations`, add:

```jsonc
"default_cache_mode": {
  "type": "string",
  "title": "Cache key and origin requests",
  "description": "Legacy settings forward nothing to the origin and cache for one hour. A cache policy replaces both the cache key and the TTLs.",
  "default": "legacy",
  "oneOf": [
    { "const": "legacy", "title": "Legacy cache settings" },
    { "const": "policy", "title": "Cache policy and origin request policy" }
  ]
},
"default_cache_policy": {
  "type": "string",
  "title": "Cache policy",
  "description": "Managed cache policy deciding the cache key and the TTLs.",
  "default": "CachingOptimized",
  "enum": [
    "CachingOptimized",
    "CachingDisabled",
    "CachingOptimizedForUncompressedObjects",
    "Amplify"
  ]
},
"default_origin_request_policy": {
  "type": "string",
  "title": "Origin request policy",
  "description": "Managed origin request policy deciding what CloudFront forwards to the origin.",
  "default": "AllViewerExceptHostHeader",
  "enum": [
    "AllViewerExceptHostHeader",
    "AllViewer",
    "CORS-S3Origin",
    "CORS-CustomOrigin",
    "UserAgentRefererHeaders"
  ]
}
```

- [ ] **Step 2: Add the same three fields, unprefixed, to the behaviors item**

In `behaviors.items.properties`, after `invocations`, add `cache_mode`, `cache_policy` and `origin_request_policy` — identical bodies to Step 1 with the `default_` prefix dropped from the key names only. The `title`, `description`, `default`, `oneOf` and `enum` values stay exactly the same.

- [ ] **Step 3: Add the collapsed CACHE section to the uiSchema for the default behavior**

In the `Distribution` category, after the element carrying the default behavior's controls and before the `ADVANCED` `Categorization`, add:

```jsonc
{
  "type": "Categorization",
  "rule": {
    "effect": "HIDE",
    "condition": {
      "scope": "#/properties/cloud_provider",
      "schema": { "not": { "const": "aws" } }
    }
  },
  "options": { "collapsable": { "label": "CACHE", "collapsed": true } },
  "elements": [
    {
      "type": "Category",
      "label": "Cache key and origin requests",
      "elements": [
        {
          "type": "Control",
          "scope": "#/properties/distribution/properties/default_cache_mode",
          "options": { "format": "radio-cards" }
        },
        {
          "type": "Control",
          "scope": "#/properties/distribution/properties/default_cache_policy",
          "rule": {
            "effect": "HIDE",
            "condition": {
              "scope": "#/properties/distribution/properties/default_cache_mode",
              "schema": { "not": { "const": "policy" } }
            }
          }
        },
        {
          "type": "Control",
          "scope": "#/properties/distribution/properties/default_origin_request_policy",
          "rule": {
            "effect": "HIDE",
            "condition": {
              "scope": "#/properties/distribution/properties/default_cache_mode",
              "schema": { "not": { "const": "policy" } }
            }
          }
        }
      ]
    }
  ]
}
```

These are the full paths the neighbouring controls in that category already use — `#/properties/distribution/properties/default_viewer_protocol_policy` is right above.

- [ ] **Step 4: Add the three controls to the behaviors detail**

In the `detail` of the behaviors array control, after the `invocations` control, add the same three controls with scopes `#/properties/cache_mode`, `#/properties/cache_policy` and `#/properties/origin_request_policy`, each hidden behind `cache_mode` not being `policy`, matching the rule shape used in Step 3.

- [ ] **Step 5: Verify the template is still valid JSON once rendered**

Run: `grep -c '"default_cache_mode"' static-files/specs/scope-configuration.json.tpl`
Expected: `1`

Run: `python3 -c "import re,sys; s=open('static-files/specs/scope-configuration.json.tpl').read(); print('balanced' if s.count('{')==s.count('}') and s.count('[')==s.count(']') else 'UNBALANCED')"`
Expected: `balanced`

- [ ] **Step 6: Render the form and read it**

Run:
```bash
cd static-files/specs/install/aws && tofu apply -var-file=terraform.tfvars
```
Registers the spec in the org named by `nrn`. Point it at the org holding the local agent, with `tags = { environment = "local", owner = "agustin" }` so the scope configuration binds to it.

Expected: creating a scope configuration in the UI shows a collapsed `CACHE` section; expanding it shows only the radio until `Cache policy and origin request policy` is selected, at which point both dropdowns appear with `CachingOptimized` and `AllViewerExceptHostHeader` preselected.

- [ ] **Step 7: Commit**

```bash
git add static-files/specs/scope-configuration.json.tpl
git commit -m "feat(specs): offer a cache mode per behavior"
```

---

### Task 2: setup reads the new fields

**Files:**
- Modify: `static-files/deployment/distribution/cloudfront/setup:129-136`
- Test: `static-files/deployment/tests/distribution/cloudfront/setup_test.bats`

**Interfaces:**
- Consumes: the scope configuration keys from Task 1.
- Produces: `distribution_default_behavior` now carries `cache_mode`, `cache_policy` and `origin_request_policy` alongside `viewer_protocol_policy`, `compress` and `invocations`. `distribution_behaviors` passes its items through untouched, so their unprefixed keys arrive as-is.

- [ ] **Step 1: Write the failing test**

Add to `setup_test.bats`:

```bash
@test "Should group the flat cache fields into the default behavior" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution += {
    "default_cache_mode": "policy",
    "default_cache_policy": "CachingDisabled",
    "default_origin_request_policy": "AllViewerExceptHostHeader"
  }')

  run_cloudfront_setup

  local expected='{
    "cache_mode": "policy",
    "cache_policy": "CachingDisabled",
    "origin_request_policy": "AllViewerExceptHostHeader"
  }'
  assert_json_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_default_behavior')" "$expected" "distribution_default_behavior"
}

@test "Should drop cache fields left empty by the UI" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution.default_cache_mode = ""')

  run_cloudfront_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -c '.distribution_default_behavior')" "{}"
}
```

This follows the harness already in the file: `run_cloudfront_setup`, `$TOFU_VARIABLES`, `assert_json_equal` / `assert_equal`, and a `CONTEXT` extended with `+=` rather than rebuilt.

- [ ] **Step 2: Run the test to verify it fails**

Run: `./testing/run_bats_tests.sh static-files`
Expected: FAIL — `cache_mode` comes back `null` because `setup` does not map it yet.

- [ ] **Step 3: Extend the jq object in setup**

Replace the `distribution_default_behavior` assignment at `setup:129-136` with:

```bash
distribution_default_behavior=$(echo "$distribution_config" | jq -c '
  {
    viewer_protocol_policy: .default_viewer_protocol_policy,
    compress: .default_compress,
    invocations: .default_invocations,
    cache_mode: .default_cache_mode,
    cache_policy: .default_cache_policy,
    origin_request_policy: .default_origin_request_policy
  } | with_entries(select(.value != null))')
```

The existing `with_entries(select(.value != null))` is what drops keys the form left empty, and the `walk` above it already turned `""` into a dropped key — no extra handling needed.

- [ ] **Step 4: Run the test to verify it passes**

Run: `./testing/run_bats_tests.sh static-files`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add static-files/deployment/distribution/cloudfront/setup static-files/deployment/tests/distribution/cloudfront/setup_test.bats
git commit -m "feat(setup): pass the cache mode through to the module"
```

---

### Task 3: Module variables

**Files:**
- Modify: `static-files/deployment/distribution/cloudfront/modules/variables.tf:39-57` (default behavior object) and `:90-105` (behaviors object)
- Test: `static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl`

**Interfaces:**
- Consumes: the keys `setup` emits in Task 2.
- Produces: `var.distribution_default_behavior.cache_mode|cache_policy|origin_request_policy` and `var.distribution_behaviors[*].cache_mode|cache_policy|origin_request_policy`, each defaulted so an unset value reads as legacy.

- [ ] **Step 1: Write the failing validation test**

Add to `cloudfront.tftest.hcl`:

```hcl
run "cache_mode_rejects_unknown_values" {
  command = plan

  variables {
    distribution_default_behavior = {
      cache_mode = "policies"
    }
  }

  expect_failures = [var.distribution_default_behavior]
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: FAIL — the run succeeds where the test expected a validation failure, because no validation exists yet.

- [ ] **Step 3: Add the fields and validations**

In `variable "distribution_default_behavior"`, add to the object type:

```hcl
    cache_mode            = optional(string, "legacy")
    cache_policy          = optional(string, "CachingOptimized")
    origin_request_policy = optional(string, "AllViewerExceptHostHeader")
```

and after the existing validations:

```hcl
  validation {
    condition     = contains(["legacy", "policy"], var.distribution_default_behavior.cache_mode)
    error_message = "cache_mode must be one of: legacy, policy."
  }

  validation {
    condition = contains([
      "CachingOptimized", "CachingDisabled",
      "CachingOptimizedForUncompressedObjects", "Amplify",
    ], var.distribution_default_behavior.cache_policy)
    error_message = "cache_policy must name a managed CloudFront cache policy."
  }

  validation {
    condition = contains([
      "AllViewerExceptHostHeader", "AllViewer",
      "CORS-S3Origin", "CORS-CustomOrigin", "UserAgentRefererHeaders",
    ], var.distribution_default_behavior.origin_request_policy)
    error_message = "origin_request_policy must name a managed CloudFront origin request policy."
  }
```

Add the same three attributes to the object inside `variable "distribution_behaviors"`, plus the list forms of the three validations:

```hcl
  validation {
    condition     = alltrue([for b in var.distribution_behaviors : contains(["legacy", "policy"], b.cache_mode)])
    error_message = "cache_mode must be one of: legacy, policy."
  }

  validation {
    condition = alltrue([
      for b in var.distribution_behaviors : contains([
        "CachingOptimized", "CachingDisabled",
        "CachingOptimizedForUncompressedObjects", "Amplify",
      ], b.cache_policy)
    ])
    error_message = "cache_policy must name a managed CloudFront cache policy."
  }

  validation {
    condition = alltrue([
      for b in var.distribution_behaviors : contains([
        "AllViewerExceptHostHeader", "AllViewer",
        "CORS-S3Origin", "CORS-CustomOrigin", "UserAgentRefererHeaders",
      ], b.origin_request_policy)
    ])
    error_message = "origin_request_policy must name a managed CloudFront origin request policy."
  }
```

- [ ] **Step 4: Run it to verify it passes**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add static-files/deployment/distribution/cloudfront/modules/variables.tf static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl
git commit -m "feat(cloudfront): accept a cache mode on every behavior"
```

---

### Task 4: Resolve managed policy names to ids

**Files:**
- Modify: `static-files/deployment/distribution/cloudfront/modules/data.tf`
- Modify: `static-files/deployment/distribution/cloudfront/modules/locals.tf`

**Interfaces:**
- Consumes: `var.distribution_default_behavior` and `var.distribution_behaviors` from Task 3.
- Produces: `local.distribution_default_cache_policy_id`, `local.distribution_default_origin_request_policy_id`, and the per-behavior lists `local.distribution_behavior_cache_policy_ids` and `local.distribution_behavior_origin_request_policy_ids`, indexed by the behavior's position. Each is `null` when that behavior is on `legacy`. Task 5 and Task 6 consume them.

- [ ] **Step 1: Add the data sources**

Append to `data.tf`:

```hcl
# Managed cache and origin request policies, looked up by name. Only the names
# the variables accept are ever requested, and only when a behavior asks for the
# policy model — a legacy-only distribution reads neither.
data "aws_cloudfront_cache_policy" "managed" {
  for_each = local.distribution_requested_cache_policies
  name     = "Managed-${each.key}"
}

data "aws_cloudfront_origin_request_policy" "managed" {
  for_each = local.distribution_requested_origin_request_policies
  name     = "Managed-${each.key}"
}
```

AWS registers these under a `Managed-` prefix (`Managed-CachingDisabled`), which is why the enum value is prefixed here rather than stored prefixed.

- [ ] **Step 2: Add the locals**

Append to `locals.tf`, before the cross-module references block:

```hcl
  # ---------------------------------------------------------------------------
  # Cache policies
  #
  # Only behaviors on the policy model contribute a name to look up, so a
  # distribution left on legacy reads no data source at all.
  # ---------------------------------------------------------------------------
  distribution_policy_behaviors = [
    for b in concat([var.distribution_default_behavior], var.distribution_behaviors) : b
    if b.cache_mode == "policy"
  ]

  distribution_requested_cache_policies = toset([
    for b in local.distribution_policy_behaviors : b.cache_policy
  ])

  distribution_requested_origin_request_policies = toset([
    for b in local.distribution_policy_behaviors : b.origin_request_policy
  ])

  distribution_default_cache_policy_id = (
    var.distribution_default_behavior.cache_mode == "policy"
    ? data.aws_cloudfront_cache_policy.managed[var.distribution_default_behavior.cache_policy].id
    : null
  )

  distribution_default_origin_request_policy_id = (
    var.distribution_default_behavior.cache_mode == "policy"
    ? data.aws_cloudfront_origin_request_policy.managed[var.distribution_default_behavior.origin_request_policy].id
    : null
  )

  distribution_behavior_cache_policy_ids = [
    for b in var.distribution_behaviors :
    b.cache_mode == "policy" ? data.aws_cloudfront_cache_policy.managed[b.cache_policy].id : null
  ]

  distribution_behavior_origin_request_policy_ids = [
    for b in var.distribution_behaviors :
    b.cache_mode == "policy" ? data.aws_cloudfront_origin_request_policy.managed[b.origin_request_policy].id : null
  ]
```

- [ ] **Step 3: Verify the module still plans on legacy**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: PASS — every existing test is legacy, so no data source is read and nothing changes.

- [ ] **Step 4: Commit**

```bash
git add static-files/deployment/distribution/cloudfront/modules/data.tf static-files/deployment/distribution/cloudfront/modules/locals.tf
git commit -m "feat(cloudfront): resolve managed policies by name"
```

---

### Task 5: Default behavior honours the mode

**Files:**
- Modify: `static-files/deployment/distribution/cloudfront/modules/main.tf:26-58`
- Test: `static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl:240` (rename `default_behavior_caching_is_fixed`)

**Interfaces:**
- Consumes: the locals from Task 4.
- Produces: nothing new. `aws_cloudfront_distribution.static.default_cache_behavior[0]` now carries either `forwarded_values` + TTLs or the two policy ids.

- [ ] **Step 1: Rename the existing test to say what it now means**

Rename `run "default_behavior_caching_is_fixed"` to `run "default_behavior_defaults_to_legacy_caching"`. Its assertions stay exactly as they are: with no `cache_mode` set, the TTLs and `forwarded_values` must still be there. This is the regression guard for the whole change.

- [ ] **Step 2: Write the failing test for the policy model**

Add to `cloudfront.tftest.hcl`:

```hcl
run "default_behavior_on_policy_drops_legacy_caching" {
  command = plan

  variables {
    distribution_default_behavior = {
      cache_mode            = "policy"
      cache_policy          = "CachingDisabled"
      origin_request_policy = "AllViewerExceptHostHeader"
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].forwarded_values) == 0
    error_message = "A behavior on the policy model must not emit forwarded_values"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].cache_policy_id != null
    error_message = "Default behavior should carry the resolved cache policy id"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].origin_request_policy_id != null
    error_message = "Default behavior should carry the resolved origin request policy id"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].default_ttl == null
    error_message = "TTLs cannot be set alongside a cache policy"
  }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: FAIL — `forwarded_values` is still emitted and `cache_policy_id` is unset.

- [ ] **Step 4: Make the block conditional**

In `main.tf`, inside `default_cache_behavior`, replace the static `forwarded_values` block and the three TTL lines with:

```hcl
    dynamic "forwarded_values" {
      for_each = var.distribution_default_behavior.cache_mode == "legacy" ? [1] : []
      content {
        query_string = false
        cookies {
          forward = "none"
        }
      }
    }

    cache_policy_id          = local.distribution_default_cache_policy_id
    origin_request_policy_id = local.distribution_default_origin_request_policy_id

    min_ttl     = var.distribution_default_behavior.cache_mode == "legacy" ? 0 : null
    default_ttl = var.distribution_default_behavior.cache_mode == "legacy" ? 3600 : null
    max_ttl     = var.distribution_default_behavior.cache_mode == "legacy" ? 86400 : null
```

`viewer_protocol_policy` and `compress` stay where they are — they belong to the behavior in both models.

- [ ] **Step 5: Run it to verify both tests pass**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: PASS, including the renamed legacy test.

- [ ] **Step 6: Commit**

```bash
git add static-files/deployment/distribution/cloudfront/modules/main.tf static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl
git commit -m "feat(cloudfront): honour the cache mode on the default behavior"
```

---

### Task 6: Ordered behaviors honour the mode

**Files:**
- Modify: `static-files/deployment/distribution/cloudfront/modules/main.tf:62-99`
- Test: `static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl`

**Interfaces:**
- Consumes: the per-behavior lists from Task 4.
- Produces: nothing new. This is the last task; after it, the mode is per behavior end to end.

- [ ] **Step 1: Write the failing test**

Add to `cloudfront.tftest.hcl`:

```hcl
run "each_behavior_keeps_its_own_cache_mode" {
  command = plan

  variables {
    distribution_default_behavior = {
      cache_mode = "legacy"
    }
    distribution_behaviors = [
      {
        path_pattern          = "/api/*"
        cache_mode            = "policy"
        cache_policy          = "CachingDisabled"
        origin_request_policy = "AllViewerExceptHostHeader"
      },
      {
        path_pattern = "/static/*"
      },
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].forwarded_values) == 1
    error_message = "The default behavior was left on legacy and should keep forwarded_values"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior[0].forwarded_values) == 0
    error_message = "The /api/* behavior is on the policy model and should drop forwarded_values"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.ordered_cache_behavior[0].cache_policy_id != null
    error_message = "The /api/* behavior should carry a resolved cache policy id"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.ordered_cache_behavior[1].forwarded_values) == 1
    error_message = "The /static/* behavior set no mode and should default to legacy"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.ordered_cache_behavior[1].cache_policy_id == null
    error_message = "A legacy behavior must not carry a cache policy id"
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: FAIL — the ordered behavior still emits `forwarded_values` and no policy id.

- [ ] **Step 3: Make the ordered block conditional**

In the `ordered_cache_behavior` dynamic block, replace the static `forwarded_values` and the three TTL lines with:

```hcl
      dynamic "forwarded_values" {
        for_each = ordered_cache_behavior.value.cache_mode == "legacy" ? [1] : []
        content {
          query_string = false
          cookies {
            forward = "none"
          }
        }
      }

      cache_policy_id          = local.distribution_behavior_cache_policy_ids[ordered_cache_behavior.key]
      origin_request_policy_id = local.distribution_behavior_origin_request_policy_ids[ordered_cache_behavior.key]

      min_ttl     = ordered_cache_behavior.value.cache_mode == "legacy" ? 0 : null
      default_ttl = ordered_cache_behavior.value.cache_mode == "legacy" ? 3600 : null
      max_ttl     = ordered_cache_behavior.value.cache_mode == "legacy" ? 86400 : null
```

`ordered_cache_behavior.key` is the list index, which is what the per-behavior locals are indexed by — the same pairing the invocation locals already use.

- [ ] **Step 4: Run it to verify it passes**

Run: `./testing/run_tofu_tests.sh static-files`
Expected: PASS

- [ ] **Step 5: Run the whole unit suite**

Run: `make test-unit && make test-tofu`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add static-files/deployment/distribution/cloudfront/modules/main.tf static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl
git commit -m "feat(cloudfront): honour the cache mode on ordered behaviors"
```

---

### Task 7: Response headers policy — schema and uiSchema

Runs BEFORE Task 2, so the form can be reviewed in the UI before any code is wired.

**Files:**
- Modify: `static-files/specs/scope-configuration.json.tpl`

**Interfaces:**
- Consumes: the CACHE section built in Task 1.
- Produces: `distribution.default_response_headers_policy` and, inside each `distribution.behaviors[]` item, `response_headers_policy`. Task 8 reads both names.

- [ ] **Step 1: Add the field to the default behavior**

In the `distribution` properties block, after `default_origin_request_policy`, add:

```jsonc
"default_response_headers_policy": {
  "type": "string",
  "title": "Response headers policy",
  "description": "Managed policy adding security or CORS headers to every response. Independent of the cache settings.",
  "default": "",
  "oneOf": [
    { "const": "", "title": "None" },
    { "const": "SecurityHeadersPolicy", "title": "Security headers" },
    { "const": "CORS-and-SecurityHeadersPolicy", "title": "CORS and security headers" },
    { "const": "SimpleCORS", "title": "Simple CORS" },
    { "const": "CORS-With-Preflight", "title": "CORS with preflight" },
    { "const": "CORS-with-preflight-and-SecurityHeadersPolicy", "title": "CORS with preflight and security headers" }
  ]
}
```

Expand the `oneOf` entries one key per line, matching the surrounding file style.

- [ ] **Step 2: Add the unprefixed field to the behaviors item**

In `behaviors.items.properties`, after `origin_request_policy`, add `response_headers_policy` — the identical body with the `default_` dropped from the key name only.

- [ ] **Step 3: Add the control to the CACHE section**

In the CACHE `Categorization` added by Task 1, append a control after the two policy controls:

```jsonc
{
  "type": "Control",
  "scope": "#/properties/distribution/properties/default_response_headers_policy"
}
```

**It carries NO `rule`.** The two controls above it are hidden when `cache_mode` is not `policy`; this one is not, because a response headers policy works in either cache mode. Adding a rule here is a defect, not a consistency fix.

- [ ] **Step 4: Add the control to the behaviors detail**

In the behaviors `detail`, after the `origin_request_policy` control, add the same control with the relative scope `#/properties/response_headers_policy`, again with no `rule`.

- [ ] **Step 5: Verify**

Run: `grep -c '"default_response_headers_policy"' static-files/specs/scope-configuration.json.tpl`
Expected: `1`

Run: `python3 -c "import json; s=open('static-files/specs/scope-configuration.json.tpl').read().replace('{{ env.Getenv \"NRN\" }}', 'organization=1'); json.loads(s); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 6: Commit**

```bash
git add static-files/specs/scope-configuration.json.tpl
git commit -m "feat(specs): offer a response headers policy per behavior"
```

---

### Task 8: Response headers policy — wiring

Runs LAST, after Task 6. Threads the field from Task 7 through the same path Tasks 2-6 built for the cache fields.

**Files:**
- Modify: `static-files/deployment/distribution/cloudfront/setup` (the `distribution_default_behavior` jq object)
- Modify: `static-files/deployment/distribution/cloudfront/modules/variables.tf` (both behavior objects)
- Modify: `static-files/deployment/distribution/cloudfront/modules/data.tf`
- Modify: `static-files/deployment/distribution/cloudfront/modules/locals.tf`
- Modify: `static-files/deployment/distribution/cloudfront/modules/main.tf` (both behavior blocks)
- Test: `static-files/deployment/tests/distribution/cloudfront/setup_test.bats`, `static-files/deployment/distribution/cloudfront/modules/cloudfront.tftest.hcl`

**Interfaces:**
- Consumes: the schema keys from Task 7; the locals and data-source conventions established in Task 4.
- Produces: nothing downstream — this is the last task.

- [ ] **Step 1: Write the failing tests**

Add to `setup_test.bats`:

```bash
@test "Should group the response headers policy into the default behavior" {
  export CONTEXT=$(echo "$CONTEXT" | jq '.providers["scope-configurations"].distribution += {
    "default_response_headers_policy": "SecurityHeadersPolicy"
  }')

  run_cloudfront_setup

  assert_equal "$(echo "$TOFU_VARIABLES" | jq -r '.distribution_default_behavior.response_headers_policy')" "SecurityHeadersPolicy"
}
```

Add to `cloudfront.tftest.hcl`:

```hcl
run "response_headers_policy_works_in_legacy_mode" {
  command = plan

  variables {
    distribution_default_behavior = {
      cache_mode              = "legacy"
      response_headers_policy = "SecurityHeadersPolicy"
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.static.default_cache_behavior[0].forwarded_values) == 1
    error_message = "A response headers policy must not disturb legacy caching"
  }

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].response_headers_policy_id != null
    error_message = "Default behavior should carry the resolved response headers policy id"
  }
}

run "no_response_headers_policy_by_default" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.static.default_cache_behavior[0].response_headers_policy_id == null
    error_message = "A behavior that names no response headers policy must not carry an id"
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./testing/run_bats_tests.sh static-files && ./testing/run_tofu_tests.sh static-files`
Expected: FAIL on both — the key is not mapped and the argument is not set.

- [ ] **Step 3: Map it in setup**

Add `response_headers_policy: .default_response_headers_policy` to the `distribution_default_behavior` jq object, as a sibling of `origin_request_policy`. The existing `with_entries(select(.value != null))` drops it when unset.

- [ ] **Step 4: Add the variable attribute and validation**

Add to both behavior object types:

```hcl
    response_headers_policy = optional(string, "")
```

and to each variable, the matching validation:

```hcl
  validation {
    condition = contains([
      "", "SecurityHeadersPolicy", "CORS-and-SecurityHeadersPolicy",
      "SimpleCORS", "CORS-With-Preflight",
      "CORS-with-preflight-and-SecurityHeadersPolicy",
    ], var.distribution_default_behavior.response_headers_policy)
    error_message = "response_headers_policy must name a managed CloudFront response headers policy, or be empty."
  }
```

For `distribution_behaviors`, wrap the same `contains(...)` in `alltrue([for b in var.distribution_behaviors : ...])` with `b.response_headers_policy`, matching how the other list validations are written.

- [ ] **Step 5: Add the data source**

Append to `data.tf`:

```hcl
data "aws_cloudfront_response_headers_policy" "managed" {
  for_each = local.distribution_requested_response_headers_policies
  name     = "Managed-${each.key}"
}
```

- [ ] **Step 6: Add the locals**

Append to the cache policies block in `locals.tf`. Note the selection differs from the cache policies: every behavior contributes, regardless of `cache_mode`, and the empty string is what excludes one.

```hcl
  distribution_requested_response_headers_policies = toset([
    for b in concat([var.distribution_default_behavior], var.distribution_behaviors) :
    b.response_headers_policy if b.response_headers_policy != ""
  ])

  distribution_default_response_headers_policy_id = (
    var.distribution_default_behavior.response_headers_policy != ""
    ? data.aws_cloudfront_response_headers_policy.managed[var.distribution_default_behavior.response_headers_policy].id
    : null
  )

  distribution_behavior_response_headers_policy_ids = [
    for b in var.distribution_behaviors :
    b.response_headers_policy != "" ? data.aws_cloudfront_response_headers_policy.managed[b.response_headers_policy].id : null
  ]
```

- [ ] **Step 7: Set the argument on both behaviors**

In `default_cache_behavior`, beside `cache_policy_id`:

```hcl
    response_headers_policy_id = local.distribution_default_response_headers_policy_id
```

In the `ordered_cache_behavior` dynamic block, beside its `cache_policy_id`:

```hcl
      response_headers_policy_id = local.distribution_behavior_response_headers_policy_ids[ordered_cache_behavior.key]
```

Neither is inside the `cache_mode` conditional.

- [ ] **Step 8: Run the full suite**

Run: `make test-unit && make test-tofu`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add static-files/deployment/distribution/cloudfront/setup static-files/deployment/distribution/cloudfront/modules static-files/deployment/tests/distribution/cloudfront/setup_test.bats
git commit -m "feat(cloudfront): apply the response headers policy in both cache modes"
```

---

## Notes for the executor

**Integration tests run against LocalStack.** `data.aws_cloudfront_cache_policy` may not be implemented there. The locals in Task 4 are written so no data source is read unless a behavior asks for the policy model, which keeps every existing LocalStack path on legacy and untouched. If an integration test is later written for the policy model, expect to stub it.

**Do not renumber or reorder behaviors.** The list order is CloudFront precedence, and the per-behavior locals are indexed by position.
