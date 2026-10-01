# Azure scope lifecycle: Front Door at scope creation

Design for moving the long-lived Front Door resources of an Azure static-files
scope out of the first deployment and into the scope's own lifecycle
(`create-scope`, `update-scope`, `delete-scope`), so a deployment only switches
the route's origin path to the build and purges the cache.

Status: approved 2026-10-01, implemented on branch feat/azure-scope-lifecycle. Azure (`front-door`
distribution) only; AWS (`cloudfront`) keeps its current behavior.

## Why

Today `scope/workflows/create.yaml` is a `no_op` (`update.yaml` and
`delete.yaml` include it), and `deployment/workflows/initial.yaml` applies the
whole stack. On Azure the first deployment therefore creates every Front Door
resource of the scope, and the custom domain is slow:

- Measured on 2026-09-29 (`azure-front-door.md`, "Customer certificate"): the
  first deployment takes ~25 minutes with a managed certificate and ~37 minutes
  with a customer certificate, because the custom domain takes ~14 minutes to
  be created before the route.
- Measured on 2026-10-01 (scope `18633875`, customer certificate): the custom
  domain was created ~13.5 minutes after the apply started; the route and the
  association followed 40 seconds later; the edge served the domain ~25
  minutes after the association.

The nullplatform control plane gives the initial deployment 10 minutes
(`Instances didn't become healthy within the 10m limit`). Past it, it marks
the deployment failed and runs `delete-deployment`, which today is
`initial.yaml` with `TOFU_ACTION=destroy` on the **same per-scope state**. That
is a rollback that tries to destroy the whole scope infrastructure. It only
fails because the original apply still holds the state lock; it is retried,
fails again, and the deployment ends `failed`. The apply finishes on its own,
and a second deployment of the same release is `finalized` in under a minute
with `No changes`.

Every first deployment of an Azure scope fails this way. The 10-minute limit
belongs to the control plane, not to this repository.

## Design

### What each action does on Azure

| Action | Today | After |
|---|---|---|
| `create-scope` | `no_op` | `apply` the whole stack, with the route pointing at a placeholder prefix |
| `update-scope` | `no_op` | `apply` the whole stack (picks up scope configuration changes) |
| `delete-scope` | `no_op` | `destroy` the whole stack |
| `start-initial`, `start-blue-green` | `apply` the whole stack | `apply` the whole stack; the scope resources already exist, so only `cdn_frontdoor_origin_path` and the purge change |
| `delete-deployment` | `destroy` the whole stack | nothing |
| `finalize-blue-green`, `rollback-deployment` | `no_op` | `no_op` (unchanged) |

The deployment owns exactly one thing: the route's origin path (and the purge
it triggers). Everything else belongs to the scope.

`delete-deployment` does nothing on Azure. If the deployment's apply failed,
the route still points where it did. If the apply succeeded and the control
plane still marked the deployment failed, the route points at the new build and
the next deployment corrects it. Reverting to the previous release is out of
scope.

On AWS nothing changes: the scope workflows stay no-ops and `delete-deployment`
still destroys.

`update.yaml` gets the same phase as `create.yaml`, but no `update-scope`
action specification is registered today (`specs/service-spec.json.tpl` lists
only `create-scope` and `delete-scope` among scope actions), so nothing
triggers it yet. Registering it is out of scope; until then a scope
configuration change reaches Front Door on the next deployment, which applies
the whole stack.

### Phase resolution

The workflow files are shared by both clouds; the cloud is chosen at runtime
by `build_context` (`DISTRIBUTION_LAYER`). Each workflow declares its phase in
`configuration:` as `STATIC_FILES_PHASE`, and a new step
`deployment/scripts/resolve_tofu_action`, run right after `build_context`,
turns phase and distribution into `TOFU_ACTION`:

| `STATIC_FILES_PHASE` | `front-door` | `cloudfront` |
|---|---|---|
| `scope-apply` (create, update) | `apply` | `skip` |
| `scope-delete` | `destroy` | `skip` |
| `deployment-apply` (initial, blue_green) | `apply` | `apply` |
| `deployment-delete` | `skip` | `destroy` |

An unknown phase or distribution is a hard error. `layer_executor`,
`compose_modules` and `do_tofu` return early, with a log line, when
`TOFU_ACTION=skip`, so no layer setup runs. That keeps the CloudFront setup,
which requires an asset, from running during a scope action.

`deployment/workflows/delete.yaml` stops overriding `TOFU_ACTION` itself and
declares `STATIC_FILES_PHASE: deployment-delete`.

### Inputs without an asset

The Front Door setup derives the storage account, the `$web` container and the
blob prefix from `.asset.url`. A scope action has no asset.

- New scope configuration attribute `distribution.azure_assets_storage_account`
  (env fallback `AZURE_ASSETS_STORAGE_ACCOUNT`). Required in scope phases;
  optional on deployments, so existing installations keep deploying without it.
- In scope phases the setup uses it for the origin and sets the blob prefix to
  `/_not-deployed/<application>-<scope>-<scope_id>`. No blob exists there, so
  the storage account answers 404 until the first deployment. The prefix is
  per scope and outside any CI layout, so the domain never serves another
  application's bundles from the shared container.
- In deployment phases the setup keeps parsing `.asset.url`, and, when the
  attribute is set, fails before any `tofu` run if the URL's account differs.
- `network/azure_dns/setup` already runs `np scope patch` with the domain; it
  now runs at `create-scope`, so the domain shows up as soon as the scope
  exists.
- `RESOURCE_TAGS_JSON` carries `deployment_id`, which is null in scope phases.
  Front Door resources do not read it; it stays as is.

### Existing scopes

No migration. The state key (`build_context`) is already per scope, and an
existing scope's state already contains the whole stack. After the upgrade:

- its next deployment finds every resource in place and only changes the
  origin path;
- deleting it destroys the stack. Before this change `delete-scope` was a
  no-op and left the resources behind.

Each environment's scope configuration needs `azure_assets_storage_account`.

## Risks to validate on the first real scope

1. **Duration of scope actions.** `create-scope` will run ~15–37 minutes. No
   limit is documented for scope actions; a service `create` of ~8 minutes
   (Azure PostgreSQL Flexible Server) completed normally.
2. **Worker idle reaper.** The agent reaps worker pods after `idleTTL` without
   activity (`nullplatform/agent` default `30m`; some installs set `15m`). If a
   long `tofu apply` does not count as activity, the worker dies mid-apply. The
   mitigation is a larger `idleTTL` in the agent installation.
3. **Scope action context.** `np service workflow exec --build-context` for a
   `create-scope` notification must carry the `scope-configurations` and
   `cloud-providers` providers. The scope workflows declare the same
   `provider_categories` as `initial.yaml`.

## Testing

- BATS for `resolve_tofu_action`: the eight combinations of the table, plus
  unknown phase and unknown distribution.
- BATS for the Front Door setup: scope phase without asset (placeholder
  prefix, account from configuration), missing `azure_assets_storage_account`,
  and a deployment whose asset account differs from the configured one.
- BATS for `layer_executor`, `compose_modules` and `do_tofu` with
  `TOFU_ACTION=skip`.
- `tests/specs/layer_selection_test.bats`: the new attribute in the schema.
- Integration `azure_frontdoor_azuredns/lifecycle_test.bats`: `create.yaml`
  (scope) → `initial.yaml` → `delete.yaml` (deployment, no change) →
  scope `delete.yaml` (everything destroyed).
- Integration `aws_cloudfront_route53/lifecycle_test.bats`: unchanged and still
  passing.

## Out of scope

- `list_instances` for Azure. It only lists CloudFront distributions and
  returns an empty list on Azure; separate change.
- Splitting the state into scope and deployment keys.
- Moving CloudFront to the scope lifecycle.
- Reverting the origin path on `delete-deployment`.
- Registering an `update-scope` action specification.
