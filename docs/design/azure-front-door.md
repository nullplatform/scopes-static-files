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
| `distribution.azure_front_door_certificate_secret` | `""` | Name of a Front Door secret in the shared profile that points to a Key Vault certificate. Non-empty: the custom domain uses `CustomerCertificate` with `cdn_frontdoor_secret_id = <profile id>/secrets/<name>` and no `_dnsauth` record is written. Env fallback `AZURE_FRONT_DOOR_CERTIFICATE_SECRET`. See [Customer certificate](#customer-certificate) |
| `security.azure_security` | `none` | `azure_waf` composes `security/azure_waf`, which creates a Front Door security policy `<app_name>-waf` in the shared profile associating an existing, customer-owned WAF policy with this scope's custom domain (`/*`). `security/none` stays the shared no-op |
| `security.azure_waf_policy_name` | none (required with `azure_waf`) | Name of the WAF policy (`Microsoft.Network/FrontDoorWebApplicationFirewallPolicies`); the setup checks it exists |
| `security.azure_waf_policy_resource_group` | `provider.azure_resource_group` | Resource group of the WAF policy |

The WAF policy follows the AWS `security/waf` model: the customer creates it
once (same tier as the profile) and the scope only associates it. Standard
profiles support custom rules only; managed rule sets need a Premium profile
and a Premium policy.

## Customer certificate

A customer certificate does not make a scope's first deployment faster.
Measured on 2026-09-29: with a managed certificate the custom domain is created
in under a minute and the certificate is issued while the route propagates;
with a customer certificate the custom domain takes ~14 minutes to be created,
before the route, so the first deployment took ~37 minutes instead of ~25.
Use it when a policy requires your own certificate (CA choice, pinning). It
mirrors AWS, where the scope references an existing ACM certificate: the
customer keeps one certificate (typically a wildcard) in Key Vault and the
shared profile holds **one** Front Door secret pointing to it; every scope's
custom domain references that secret by name.

Facts that shape it (Microsoft docs, checked 2026-09-29):

- With a customer certificate Front Door approves domain ownership on its own
  when the certificate's CN/SAN matches the domain, so the layer writes no
  `_dnsauth` TXT record (`count = 0`, `distribution_validation_record` is
  null).
- The secret references the certificate's **versionless** id, so Front Door
  follows renewals ("Latest"); a new version deploys within 72 hours.
- Key Vault access is a **user-assigned managed identity** attached to the
  profile, with `Key Vault Secrets User` on an RBAC-mode vault. Registering the
  `Microsoft.AzureFrontDoor-Cdn` service principal with an access policy is
  being deprecated and is not used.
- Certificates must be RSA (no EC), carry the full chain, be imported from a
  PFX as a Key Vault certificate object, and live in the same subscription.

Split of responsibilities:

- **Scope layer** (azurerm 3.117, unchanged): only the secret's name. The id is
  built from the profile data source (`<profile id>/secrets/<name>`), so the
  scope needs no Key Vault access and no new role; `CDN Profile Contributor`
  covers the custom domain. The 3.117 `tls` argument is
  `cdn_frontdoor_secret_id`.
- **Requirements module** (azurerm >= 4.15): a user-assigned identity
  (`id-<profile>` by default, located in the profile's resource group region
  unless `front_door_identity_location` is set), attached to the profile (the
  `identity` block only exists from azurerm 4.15), the role assignment and the
  secret, behind `certificate_key_vault_certificate_id`. User-assigned, not
  system-assigned: `azurerm_cdn_frontdoor_profile` exports only `id` and
  `resource_guid`, so a system identity's principal id cannot feed the role
  assignment (a real plan failed with `Missing required argument` on
  `principal_id`). Only for a profile the module creates: it does not change
  an existing profile's identity. Attaching the identity updates the profile
  in place (verified with a real `tofu plan` against a v2.0.0-created
  profile).

Role propagation: Azure RBAC can take minutes to reach Key Vault, and the
provider does not retry the secret. The secret `depends_on` the role
assignment, which sets `principal_type = "ServicePrincipal"` and
`skip_service_principal_aad_check` so ARM does not look up a just-created
identity in Entra ID. If the first apply still fails on the secret with a Key
Vault access error, applying again succeeds; a `time_sleep` would add the
`hashicorp/time` provider to every consumer for a one-off wait, so the module
documents the re-apply instead.

Example issuance, a Let's Encrypt wildcard with DNS-01 on Azure DNS (lego
defaults to EC keys, hence `--key-type rsa2048`):

```bash
AZURE_SUBSCRIPTION_ID=<subscription> AZURE_RESOURCE_GROUP=<dns-zone-rg> \
lego --email ops@example.com --dns azuredns --key-type rsa2048 \
  -d '*.np.example.com' run
openssl pkcs12 -export -passout pass: \
  -in .lego/certificates/_.np.example.com.crt \
  -inkey .lego/certificates/_.np.example.com.key \
  -out wildcard-np-example-com.pfx
az keyvault certificate import --vault-name certs-kv \
  --name wildcard-np-example-com --file wildcard-np-example-com.pfx
```

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

## Requirements module

`static-files/specs/requirements/azure` is the Azure counterpart of
`requirements/aws`: an OpenTofu module the customer's infrastructure layer
consumes. It creates what the scope expects to exist and never creates
itself: the shared Front Door profile, one endpoint per environment
(`<prefix>-<env>`), an optional empty WAF policy, and the agent identity's
role assignments (Storage Blob Data Contributor on the state container, CDN
Profile Contributor on the profile, DNS Zone Contributor on the zone, Reader
on the assets account and on the WAF policy). Its outputs map one to one to
the `distribution.azure_front_door_*` and `security.azure_waf_policy_name`
fields of each environment's provider config.

Unlike the scope's own layers it requires `azurerm >= 4.15, < 5.0` (v3.0.0;
v2.x accepted `>= 3.117`): the customer certificate needs the profile's
`identity` block, added in azurerm 4.15, and the first consumer's
infrastructure layer runs 4.x. Optionally it also creates the customer
certificate's identity, `Key Vault Secrets User` assignment and Front Door
secret (see [Customer certificate](#customer-certificate)). The
principal id is an input (the object id), not a lookup: guest users in the
customer tenant cannot read service principals. The assets storage account
stays a prerequisite, like the S3 bucket on AWS.

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

- Creating or managing WAF policies from the scope (it only attaches an existing one; the requirements module can create an empty one), Private Link and Premium-only features.
- Supporting `np asset push` for blob storage (platform side).
- Migrating scopes created with `blob-cdn`: none could have been created
  since 2025-08-15.
