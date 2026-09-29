# Azure Front Door distribution

Design for serving static-files scopes on Azure with Azure Storage (static
website) as the origin and Azure Front Door Standard/Premium as the CDN,
replacing the `blob-cdn` layer built on Azure CDN classic.

Status: approved 2026-09-29, not yet implemented. Analysis and the topology
decision: https://claude.ai/artifact/EiAz7VHLDoAqUFgG354h1r

## Why

`distribution/blob-cdn` creates an `azurerm_cdn_profile` with SKU
`Standard_Microsoft`, which is *Azure CDN Standard from Microsoft (classic)*.
Microsoft stopped accepting new classic profiles, new custom domains and new
managed certificates on 2025-08-15 and retires the service on 2027-09-30. A new
scope on that layer fails against a real subscription; the layer only passes CI
because `testing/docker/azure-mock` emulates the classic API. Azure Front Door
Standard/Premium is the successor and the only supported path.

## Topology: shared profile and endpoint, one route per scope

Front Door bills and limits per **profile** (Standard: 35 USD/month base,
10 endpoints, 100 custom domains, 100 routes, 100 origin groups; Premium:
330 USD/month, 25/500/200/200). The **endpoint** owns the `*.azurefd.net`
hostname and the purge operation. A **route** binds an endpoint to an origin
group and, optionally, to custom domains and rule sets.

Decision (option C in the analysis):

- The customer creates **one profile and one endpoint per environment** in its
  own infrastructure, the same way it already provides the DNS zone and the
  assets storage account. Their names are declared in the scope configuration.
- Each scope creates, inside that endpoint: an origin group, an origin pointing
  to the storage account's static-website host, a rule set with the SPA
  fallback, a route with `cdn_frontdoor_origin_path` set to the asset prefix,
  a custom domain `<app>-<scope>.<zone>` with a managed certificate, the
  `_dnsauth` TXT record that validates it, and the association between the
  domain and the route.
- The route is **not** linked to the endpoint's default domain
  (`link_to_default_domain = false`). Front Door routes by host name, so the
  custom domain is what identifies the scope. **A DNS zone is therefore
  mandatory**: a scope without a network layer cannot be served.
- Cache invalidation is a purge on the shared endpoint, filtered by the
  scope's domain, triggered whenever the origin path changes. Same mechanism
  as CloudFront's `origin_path` + invalidation.
- `delete-scope` removes only the scope's own resources. Profile and endpoint
  are read through data sources and never destroyed by a scope.
- The tier (Standard or Premium) is a property of the profile the customer
  creates. It is **not** a scope-configuration field.

Rejected alternatives: profile per scope (35 USD/month per scope, and the
Standard cap of 500 profiles per subscription); profile shared with one
endpoint per scope (keeps a hostname per scope but caps at 10 scopes per
environment on Standard).

## Scope configuration

New fields under `distribution`, required when `cloud_provider = "azure"`:

| Field | Meaning |
|-------|---------|
| `azure_front_door_profile` | Name of the shared Front Door profile |
| `azure_front_door_endpoint` | Name of the shared endpoint inside that profile |
| `azure_front_door_resource_group` | Resource group of the profile. Optional; defaults to `provider.azure_resource_group` |

`azure_distribution` offers a single value, `front-door`, which is also the
default. `blob-cdn` is removed from the enum and from the tree.

Environment-variable fallbacks, for local runs and integration tests:
`AZURE_FRONT_DOOR_PROFILE`, `AZURE_FRONT_DOOR_ENDPOINT`,
`AZURE_FRONT_DOOR_RESOURCE_GROUP`.

## Configurable behavior

Optional scope-configuration fields; an unset field keeps the default, which
is the behavior the layer shipped with.

| Field | Default | Effect |
|-------|---------|--------|
| `distribution.azure_front_door_cached_path_prefixes` | `["/static/"]` | Paths `StaticCache` caches long; `NoCacheOutsideStatic` disables caching for every path that starts with none of them. 1 to 10 entries, each starting with `/` |
| `distribution.azure_front_door_cache_days` | `7` | Edge cache duration of `StaticCache` (`<days>.00:00:00`), 1 to 365. The override keeps `query_string_caching_behavior = IgnoreQueryString` |
| `distribution.azure_front_door_security_headers` | `false` | Adds the `SecurityHeaders` rule (order 4, no conditions): Strict-Transport-Security `max-age=31536000; includeSubDomains`, X-Content-Type-Options `nosniff`, X-Frame-Options `SAMEORIGIN`, Referrer-Policy `strict-origin-when-cross-origin`, all `Overwrite` |
| `distribution.azure_front_door_content_security_policy` | `""` | Fifth header of `SecurityHeaders` when non-empty. Ignored, with a setup warning, while the headers are off |
| `security.azure_security` | `none` | `azure_waf` composes `security/azure_waf`, which creates a Front Door security policy `<app_name>-waf` in the shared profile associating an existing, customer-owned WAF policy with this scope's custom domain (`/*`). `security/none` stays the shared no-op |
| `security.azure_waf_policy_name` | none (required with `azure_waf`) | Name of the WAF policy (`Microsoft.Network/FrontDoorWebApplicationFirewallPolicies`); the setup checks it exists |
| `security.azure_waf_policy_resource_group` | `provider.azure_resource_group` | Resource group of the WAF policy |

The WAF policy follows the AWS `security/waf` model: the customer creates it
once (same tier as the profile) and the scope only associates it. Standard
profiles support custom rules only; managed rule sets need a Premium profile
and a Premium policy.

## Layer contract

The distribution layer keeps the existing cross-layer contract, so
`network/azure_dns` needs no structural change:

- Produces `local.distribution_target_domain` = the shared endpoint's
  `host_name`, and `local.distribution_record_type = "CNAME"`.
- Consumes `local.network_full_domain`, `local.network_domain`,
  `var.network_subdomain`, `var.network_dns_zone_name` and the new
  `var.network_dns_zone_resource_group`.

`network/azure_dns` gets one fix: the setup script validates
`azure_dns_zone_resource_group` but never forwards it, and the module looks the
zone up in the provider's resource group instead. The setup now exports
`network_dns_zone_resource_group` and the module uses it for the zone data
source and every record.

## Asset publishing

The layer derives storage account, container and blob prefix from
`asset.url`, expecting `https://<account>.blob.core.windows.net/<container>/<prefix>`.
CI publishes the bundle and registers the asset itself, exactly as the AWS
reference CI does with `aws s3 cp` + `np asset create`:

```bash
az storage blob upload-batch --account-name "$STORAGE_ACCOUNT" \
  --destination '$web' --destination-path "frontends/$application_id/$build_id" \
  --source ./dist --auth-mode login
np asset create --body "{\"type\":\"bundle\",\"name\":\"main\",\"build_id\":$build_id,
  \"application_id\":$application_id,
  \"url\":\"https://$STORAGE_ACCOUNT.blob.core.windows.net/\$web/frontends/$application_id/$build_id\",
  \"metadata\":{}}"
```

The container may arrive URL-encoded (`%24web`); the setup decodes it.

## Worker image

The Azure path shells out to `az` (`azure_dns/setup` today, the purge from
now on). The worker image only ships `aws-cli`; it gets `azure-cli` installed
through pip, the same way the integration test runner does. The purge uses
`az rest` against the ARM purge action so no CLI extension is needed.

## Provider version

`provider/azure` pins `azurerm >= 3.117, < 4.0`. The Front Door resources and
data sources exist in that range; the 3.x block names (`url_rewrite_action`,
`url_file_extension_condition`) are what the module uses, and the integration
overrides still rely on `skip_provider_registration`, which 4.x removed.
Modules that run `tofu test` in isolation carry a `test_versions.tf` (skipped
by `compose_modules`) with the same constraint, otherwise `tofu test` resolves
the newest provider and the 3.x block names stop parsing.

## Testing

- BATS for the setup script (asset URL parsing, `$web` decoding, missing
  profile/endpoint, `MODULES_TO_USE`).
- `tofu test` for the module with `mock_provider "azurerm"`: names, origin,
  origin path normalization, route flags, custom domain, TXT record,
  precondition when `network_full_domain` is empty, outputs.
- Azure mock (`nullplatform/scope-testing`, git submodule `testing/`) learns
  the AFD resources (`afdEndpoints`, `routes`, `originGroups`, `origins`,
  `ruleSets`, `rules`, profile-level `customDomains`, `purge`) and DNS `TXT`
  records. Purges are recorded and exposed at `GET /mock/afd/purges`.
- Integration case `azure_frontdoor_azuredns`: seeds profile, endpoint, zone
  and storage account; runs `initial.yaml`; asserts route, domain, TXT, CNAME
  and purge; runs `delete.yaml`; asserts the scope's resources are gone and the
  shared profile and endpoint remain.
- A real end-to-end run on an Azure subscription before release. Nothing on
  the Azure path has ever run outside mocks.

## Out of scope

- Creating or managing WAF policies (the scope only attaches an existing one), Private Link and Premium-only features.
- Supporting `np asset push` for blob storage (platform side).
- Migrating scopes created with `blob-cdn`: none could have been created
  since 2025-08-15.
