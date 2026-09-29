# specs/requirements/azure

Azure resources and RBAC the static-files scope expects to exist before its
first deployment, consumed as an OpenTofu module by the customer's
infrastructure layer (the Azure counterpart of [`../aws`](../aws/README.md)).

The scope never creates or deletes these: every static-files scope of an
environment adds its own route and custom domain to a shared Front Door
endpoint, and the agent identity needs a handful of role assignments to do it.
This module creates:

- **A Front Door profile** (`create_front_door`, default on) and **one endpoint
  per environment**, named `<front_door_endpoint_prefix>-<environment>`.
- **An empty Front Door WAF policy** (`create_waf_policy`, default off) the scopes
  attach with `security.azure_security = azure_waf`. It has no rules: add your
  own custom rules. Managed rule sets (DefaultRuleSet, BotManager) need
  `front_door_sku = "Premium_AzureFrontDoor"`.
- **Role assignments for the agent identity** (`create_role_assignments`,
  default on):

  | Key in `role_assignment_ids` | Role | Scope |
  |---|---|---|
  | `state_container` | Storage Blob Data Contributor | `<state_storage_account_id>/blobServices/default/containers/<state_container_name>` |
  | `front_door_profile` | CDN Profile Contributor | The created profile, or `existing_front_door_profile_id` |
  | `dns_zone` | DNS Zone Contributor | `dns_zone_id` |
  | `assets_storage_account` | Reader | `assets_storage_account_id` (the distribution layer reads it with a data source) |
  | `waf_policy` | `waf_policy_role_definition_name` (default Reader) | The created policy, or `existing_waf_policy_id`. Only when one of them is set |

- **A customer certificate** (`certificate_key_vault_certificate_id`, default
  off): a system-assigned identity on the profile, `Key Vault Secrets User`
  for it on the vault, and one Front Door secret every scope references. See
  [Customer certificate](#customer-certificate).

It needs `azurerm >= 4.15, < 5.0` (4.15 added the profile's `identity` block)
and declares no provider block: the consuming stack configures `azurerm` and
the subscription. Stacks still on azurerm 3.x stay on v2.x of this module.

## Usage

```hcl
module "static_files_requirements" {
  source = "git::https://github.com/nullplatform/scopes-static-files.git//static-files/specs/requirements/azure?ref=<tag>"

  front_door_profile_name        = "static-files"
  front_door_resource_group_name = azurerm_resource_group.cdn.name
  environments                   = ["development", "staging", "production"]

  agent_principal_id        = var.agent_principal_object_id
  state_storage_account_id  = azurerm_storage_account.tfstate.id
  state_container_name      = "tfstate"
  dns_zone_id               = azurerm_dns_zone.public.id
  assets_storage_account_id = azurerm_storage_account.assets.id

  create_waf_policy = true
  waf_policy_name   = "staticfileswaf"

  tags = { managed-by = "opentofu" }
}
```

To reuse a profile you already have, set `create_front_door = false` and
`existing_front_door_profile_id`; the module then creates no profile or
endpoints and scopes `CDN Profile Contributor` to that profile.

### Wiring the scope configuration

The outputs feed one `nullplatform_provider_config` per environment, with the
same attributes as [`../../install/azure/main.tf`](../../install/azure/main.tf):

```hcl
locals {
  environments = {
    development = { nrn = "organization=1:account=2:namespace=3", resource_group = "static-dev-rg" }
    staging     = { nrn = "organization=1:account=2:namespace=4", resource_group = "static-stg-rg" }
    production  = { nrn = "organization=1:account=2:namespace=5", resource_group = "static-prd-rg" }
  }
}

resource "nullplatform_provider_config" "static_files" {
  for_each = local.environments

  nrn        = each.value.nrn
  type       = module.scope_definition.provider_specification_slug # the slug, not the id
  dimensions = {}

  attributes = jsonencode({
    cloud_provider = "azure"

    provider = {
      azure_subscription_id       = var.azure_subscription_id
      azure_resource_group        = each.value.resource_group
      azure_state_storage_account = azurerm_storage_account.tfstate.name
      azure_state_container       = "tfstate"
      azure_state_resource_group  = azurerm_storage_account.tfstate.resource_group_name
      azure_state_auth            = "azuread"
    }

    network = {
      azure_network                 = "azure_dns"
      azure_dns_zone_name           = azurerm_dns_zone.public.name
      azure_dns_zone_resource_group = azurerm_dns_zone.public.resource_group_name
    }

    distribution = {
      azure_distribution              = "front-door"
      azure_front_door_profile        = module.static_files_requirements.front_door_profile_name
      azure_front_door_endpoint       = module.static_files_requirements.front_door_endpoint_names[each.key]
      azure_front_door_resource_group = module.static_files_requirements.front_door_resource_group_name
      # Only with a customer certificate; omit it for managed certificates.
      azure_front_door_certificate_secret = module.static_files_requirements.front_door_certificate_secret_name
    }

    security = {
      azure_security                  = "azure_waf"
      azure_waf_policy_name           = module.static_files_requirements.waf_policy_name
      azure_waf_policy_resource_group = module.static_files_requirements.front_door_resource_group_name
    }
  })
}
```

Without a WAF policy, use `security = { azure_security = "none" }`.

## Variables

| Variable | Default | Description |
|---|---|---|
| `agent_principal_id` | `""` | Object id of the agent's service principal or managed identity. Required when `create_role_assignments` is true. |
| `agent_principal_type` | `ServicePrincipal` | `ServicePrincipal` (managed identities too), `User` or `Group`. |
| `create_role_assignments` | `true` | When false, no role assignment is created. |
| `state_storage_account_id` | `""` | Id of the state storage account. Required with role assignments. |
| `state_container_name` | `tfstate` | State container; the blob role is scoped to it only. |
| `dns_zone_id` | `""` | Id of the public DNS zone. Required with role assignments. |
| `assets_storage_account_id` | `""` | Id of the static-website storage account. Required with role assignments. |
| `create_front_door` | `true` | Create the profile and the endpoints. |
| `existing_front_door_profile_id` | `""` | Existing profile, required when `create_front_door` is false. |
| `front_door_profile_name` | `static-files` | Profile name. |
| `front_door_resource_group_name` | `""` | Resource group of the profile and of the created WAF policy. |
| `front_door_sku` | `Standard_AzureFrontDoor` | `Standard_AzureFrontDoor` or `Premium_AzureFrontDoor`; also the WAF policy SKU. |
| `environments` | `["development","staging","production"]` | One endpoint per entry. |
| `front_door_endpoint_prefix` | `static-files` | Endpoint names are `<prefix>-<env>`: letters, digits and hyphens, start and end alphanumeric, at most 46 chars. |
| `create_waf_policy` | `false` | Create an empty WAF policy. |
| `waf_policy_name` | `staticfileswaf` | Letters and digits only, starting with a letter, up to 128 chars. |
| `waf_mode` | `Prevention` | `Detection` or `Prevention`. |
| `existing_waf_policy_id` | `""` | Existing WAF policy the scopes attach; gets the WAF role assignment. |
| `waf_policy_role_definition_name` | `Reader` | Role on the WAF policy. See [WAF policy permissions](#waf-policy-permissions). |
| `certificate_key_vault_id` | `""` | Id of the Key Vault (RBAC mode) with the customer certificate. Required with `certificate_key_vault_certificate_id`. |
| `certificate_key_vault_certificate_id` | `""` | **Versionless** certificate id (`https://<vault>.vault.azure.net/certificates/<name>`); a trailing version is rejected. Empty keeps managed certificates. |
| `front_door_certificate_secret_name` | `customer-certificate` | Front Door secret name: 2-260 letters, digits or hyphens, starting alphanumeric. |
| `tags` | `{}` | Tags on the profile, endpoints and WAF policy. |

## Outputs

| Output | Description |
|---|---|
| `front_door_profile_id` | Profile id (created or existing). |
| `front_door_profile_name` | Feeds `distribution.azure_front_door_profile`. |
| `front_door_resource_group_name` | Feeds `distribution.azure_front_door_resource_group`. |
| `front_door_endpoint_names` | Map environment → endpoint name. Feeds `distribution.azure_front_door_endpoint`. |
| `front_door_endpoint_host_names` | Map environment → `*.azurefd.net` host name. |
| `waf_policy_id` | Created policy id, or null. |
| `waf_policy_name` | Created policy name, or null. Feeds `security.azure_waf_policy_name`. |
| `role_assignment_ids` | Map of the keys in the table above → role assignment id. |
| `front_door_certificate_secret_name` | Secret name, or null without a customer certificate. Feeds `distribution.azure_front_door_certificate_secret`. |
| `front_door_principal_id` | Principal id of the profile's system-assigned identity, or null. |

## The agent's principal id

`agent_principal_id` is the **object id** of the agent's service principal (or
managed identity), not its client id. Pass it as a value: guest users in the
customer tenant usually cannot read service principals from Entra ID, so a
`data "azuread_service_principal"` lookup fails for them. Either the customer
gives you the object id, or the customer applies this module themselves.

## WAF policy permissions

The scope's `azure_waf` layer reads the policy with a data source and creates
an `azurerm_cdn_frontdoor_security_policy` in the profile. The security policy
write (`Microsoft.Cdn/profiles/securityPolicies/write`) is covered by
`CDN Profile Contributor`; the policy read by `Reader`.

Azure also defines `Microsoft.Network/frontDoorWebApplicationFirewallPolicies/join/action`
("Joins a Web Application Firewall Policy"). Microsoft does not document
whether associating a policy through a security policy checks it; the only
built-in roles that include it are `Network Contributor` and `Contributor`.
The module keeps `Reader`. If the first `azure_waf` deployment fails with
`LinkedAuthorizationFailed` on the policy, set
`waf_policy_role_definition_name = "Network Contributor"` (scoped to the policy
only), or grant a custom role with `.../frontDoorWebApplicationFirewallPolicies/read`
and `.../join/action`.

## Customer certificate

By default every scope gets a Front Door managed certificate, validated with a
`_dnsauth` TXT record; issuing it adds several minutes to a scope's first
deployment. Instead, the scopes can serve one certificate you keep in Key Vault
(for example a Let's Encrypt wildcard `*.np.example.com`), the way AWS scopes
reference an existing ACM certificate:

```hcl
module "static_files_requirements" {
  # ...
  certificate_key_vault_id             = azurerm_key_vault.certs.id
  certificate_key_vault_certificate_id = "https://certs-kv.vault.azure.net/certificates/wildcard-np-example-com"
}
```

The module then:

- adds `identity { type = "SystemAssigned" }` to the profile (an in-place
  update, the profile is not replaced);
- grants that identity `Key Vault Secrets User` on `certificate_key_vault_id`;
- creates the Front Door secret `front_door_certificate_secret_name` pointing at
  the certificate.

Set `distribution.azure_front_door_certificate_secret` to the
`front_door_certificate_secret_name` output. Each scope's custom domain then
uses `CustomerCertificate` and skips the `_dnsauth` record: Front Door approves
the domain because the certificate's CN/SAN covers it.

Requirements:

- **Key Vault in RBAC mode**, in the same subscription as the profile. The
  identity applying this module needs rights to create role assignments on the
  vault (Owner or User Access Administrator); whoever imports the certificate
  needs `Key Vault Certificates Officer`. Registering the
  `Microsoft.AzureFrontDoor-Cdn` service principal with an access policy is the
  deprecated alternative and is not used.
- **RSA key** (Front Door does not accept EC), **full chain**, imported as a
  Key Vault **certificate** object from a PFX.
- **Versionless id**, so Front Door follows renewals ("Latest"): a new version
  imported into Key Vault reaches the edge within 72 hours, with no change to
  the scopes or to this module.
- **`create_front_door = true`**: the module does not change the identity of a
  profile it does not own. With an existing profile, create the identity, the
  role assignment and the secret yourself.

**First apply.** Azure RBAC can take a few minutes to reach Key Vault after the
role assignment is created, and the provider does not retry the secret. If the
first apply fails on `azurerm_cdn_frontdoor_secret.customer_certificate` with a
Key Vault access error, wait a couple of minutes and apply again; the identity
and the role assignment are already in place.

Example: a Let's Encrypt wildcard with [lego](https://go-acme.github.io/lego/),
DNS-01 through Azure DNS (the identity running lego needs `DNS Zone
Contributor` on the zone):

```bash
# After `az login`; lego finds the zone through Azure Resource Graph.
AZURE_SUBSCRIPTION_ID=<subscription> AZURE_RESOURCE_GROUP=<dns-zone-rg> \
lego --email ops@example.com --dns azuredns --key-type rsa2048 \
  -d '*.np.example.com' run

# lego writes the full chain to the .crt; bundle it with the key as a PFX.
openssl pkcs12 -export -passout pass: \
  -in .lego/certificates/_.np.example.com.crt \
  -inkey .lego/certificates/_.np.example.com.key \
  -out wildcard-np-example-com.pfx

az keyvault certificate import --vault-name certs-kv \
  --name wildcard-np-example-com --file wildcard-np-example-com.pfx

# Versionless id: the certificate id without its last segment.
az keyvault certificate show --vault-name certs-kv \
  --name wildcard-np-example-com --query id -o tsv | sed 's|/[^/]*$||'
```

Renewing is `lego ... renew` plus the same `openssl` and `az keyvault
certificate import`: the import adds a version and Front Door picks it up.

## Assets storage account (prerequisite)

Like the S3 bucket on AWS, the storage account that holds the bundles stays a
customer prerequisite: CI uploads to it and it usually lives with the
customer's other storage. Enable the static website, with `index.html` as the
error document too:

```bash
az storage blob service-properties update \
  --account-name <assets_storage_account> \
  --static-website --index-document index.html --404-document index.html
```

## Versioning

Point the module `source` at a **tag**, never a branch:

```hcl
?ref=v0.2.0   # immutable
?ref=main     # moves with every push
```
