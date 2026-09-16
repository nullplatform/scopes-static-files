# Configurable cache mode

Design for making CloudFront's cache configuration part of the scope configuration,
instead of the fixed legacy settings the module hardcodes today.

Status: design only. Nothing here is implemented.

Driven by a customer running several front-end scopes who needs some of them to bypass
the CDN cache entirely, and who asked for the choice to be presented the way the AWS
console presents it: a radio between *Legacy cache settings* and *Cache policy and
origin request policy*.

**Premise: legacy stays the default.** Every scope configuration already registered was
created without these fields. If the default were anything other than the current
behaviour, adding them would silently change how existing distributions cache. That is
not a preference, it is what keeps this change additive.

## Current state

`v1.0.0` made behaviors configurable — a default behavior flattened into `distribution.*`
plus an ordered `distribution.behaviors[]` list, each carrying its viewer protocol, its
compression flag and its invocations. Caching was deliberately left out. From
`modules/variables.tf`:

> Caching itself is not configurable: every behavior forwards nothing to the origin and
> keeps the same TTLs the scope has always used.

Every behavior the module emits, default and ordered alike, gets the same block:

```hcl
forwarded_values {
  query_string = false
  cookies { forward = "none" }
}
min_ttl     = 0
default_ttl = 3600
max_ttl     = 86400
```

There is no cache policy anywhere in the module: `main.tf`, `locals.tf`, `data.tf` and
`variables.tf` have zero references to `cache_policy` or `origin_request_policy`.

## Requirements

1. A scope configuration can choose, per behavior, between legacy cache settings and the
   cache policy model.
2. Legacy is the default and reproduces today's behaviour exactly.
3. Choosing the policy model offers `AllViewerExceptHostHeader` as the origin request
   policy without the user having to pick it.
4. The form stays readable: cache is a collapsed section, not five more fields in the
   main flow.

## Design

### Schema

Three fields, added to the default behavior and to each item of
`distribution.behaviors[]`. The two models are discriminated by an explicit field rather
than inferred from whether a policy is set — inference reads as a shortcut, does not map
onto the console screen the customer referenced, and leaves no natural place to express
the preselected origin request policy.

On the default behavior they carry the `default_` prefix — `default_cache_mode`,
`default_cache_policy`, `default_origin_request_policy` — because the form resolves only
two levels of nesting, which is why `default_viewer_protocol_policy`, `default_compress`
and `default_invocations` are already flat. `setup` folds them back into the single
object the module takes. Inside `behaviors[]` there is no prefix: the nesting is one
level there, so the names are `cache_mode`, `cache_policy` and `origin_request_policy`.

```jsonc
"cache_mode": {
  "type": "string",
  "title": "Cache key and origin requests",
  "default": "legacy",
  "oneOf": [
    { "const": "legacy", "title": "Legacy cache settings" },
    { "const": "policy",  "title": "Cache policy and origin request policy" }
  ]
},
"cache_policy": {
  "type": "string",
  "title": "Cache policy",
  "default": "CachingOptimized",
  "enum": [
    "CachingOptimized",
    "CachingDisabled",
    "CachingOptimizedForUncompressedObjects",
    "Amplify"
  ]
},
"origin_request_policy": {
  "type": "string",
  "title": "Origin request policy",
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

Managed policies only. A closed list renders as a dropdown, cannot carry a typo into an
apply, and needs no id validation. Custom policies created outside the platform are out
of scope for this change; adding them later means one `custom` const plus an id field,
without disturbing what is designed here.

### uiSchema

The file already has the pattern, in the block that groups the advanced distribution
categories:

```jsonc
"options": { "collapsable": { "label": "ADVANCED", "collapsed": true } }
```

Cache reuses it as its own collapsed `Categorization` labelled `CACHE`, so a scope that
does not care about caching never sees the fields. Inside it:

- `cache_mode` as `radio-cards`, the format the file already uses for this kind of
  either/or choice.
- `cache_policy` and `origin_request_policy` as plain controls, each behind a `HIDE`
  rule keyed on `cache_mode` not being `policy` — the same rule mechanism the file uses
  to hide the AWS fields when the provider is Azure.

The behaviors array carries the same three controls inside its `detail`, next to
`viewer_protocol_policy`, `compress` and `invocations`.

### Terraform

`forwarded_values` and `cache_policy_id` are mutually exclusive on a behavior, and the
TTL arguments cannot be set alongside a cache policy either. So the legacy block becomes
conditional and the policy ids resolve to `null` when unused:

```hcl
dynamic "forwarded_values" {
  for_each = var.distribution_default_behavior.cache_mode == "legacy" ? [1] : []
  content {
    query_string = false
    cookies { forward = "none" }
  }
}

cache_policy_id          = local.distribution_default_cache_policy_id
origin_request_policy_id = local.distribution_default_origin_request_policy_id

min_ttl     = var.distribution_default_behavior.cache_mode == "legacy" ? 0 : null
default_ttl = var.distribution_default_behavior.cache_mode == "legacy" ? 3600 : null
max_ttl     = var.distribution_default_behavior.cache_mode == "legacy" ? 86400 : null
```

Ids come from `data.aws_cloudfront_cache_policy` and
`data.aws_cloudfront_origin_request_policy` looked up by name. Both data sources are new;
they resolve over the set of names the enum allows, and the locals pick per behavior.

### Backward compatibility

A scope configuration stored before this change has no `cache_mode`. The schema default
supplies `legacy`, the module takes the `forwarded_values` branch, and the plan against an
existing distribution is empty. No migration of stored provider data is required — which
is the point of the premise above, and the difference between this change and the one
that renamed `lambda_associations`.

## Testing

`cloudfront.tftest.hcl` covers behaviors already. The cases this adds:

- legacy behavior emits `forwarded_values` and the three TTLs
- policy behavior emits neither, and carries both policy ids
- a distribution whose default behavior is legacy while an ordered behavior is on policy,
  proving the choice is per behavior
- an unset `cache_mode` produces the same plan as an explicit `legacy`

BATS covers `build_context` reading the new fields out of the scope configuration.

## Local validation

The spec is registered by the tofu module in `static-files/specs/install/aws`, so the
form can be iterated without publishing an image: apply, reload the UI, read the rendered
form. Only the deployment phase needs the worker image.

The agent to target is the local one, whose tags are the match key for the install's
`tags` variable:

```
-tags environment:local,owner:agustin
```

Its worker image is built locally under the ECR name and never pushed, so the agent
resolves it from the local Docker daemon.

### Response headers policy

A fourth field, `default_response_headers_policy` on the default behavior and
`response_headers_policy` inside `behaviors[]`, carrying the managed security and CORS
policies:

```jsonc
{
  "type": "string",
  "title": "Response headers policy",
  "default": "",
  "oneOf": [
    { "const": "",                                          "title": "None" },
    { "const": "SecurityHeadersPolicy",                     "title": "Security headers" },
    { "const": "CORS-and-SecurityHeadersPolicy",            "title": "CORS and security headers" },
    { "const": "SimpleCORS",                                "title": "Simple CORS" },
    { "const": "CORS-With-Preflight",                       "title": "CORS with preflight" },
    { "const": "CORS-with-preflight-and-SecurityHeadersPolicy", "title": "CORS with preflight and security headers" }
  ]
}
```

**It is not gated behind `cache_mode`.** The AWS console groups the three policy fields
under one heading, but that is a UI grouping, not the resource's shape:
`response_headers_policy_id` is not mutually exclusive with `forwarded_values` — only the
cache key and the TTLs are. Gating it would force anyone who wants HSTS to also change
their caching model. The field is always visible, and it sits in the CACHE section beside
`cache_mode` rather than inside the pair that `cache_mode` reveals.

`""` is the default and means no policy: the module emits `response_headers_policy_id =
null`, which is what every distribution does today.

## Out of scope

- **Custom (non-managed) policies.** See the schema section.
- **Azure.** The `blob-cdn` distribution has no equivalent model; these fields stay under
  the AWS branch of the form, as the rest of the CloudFront settings already do.
