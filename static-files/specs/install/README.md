# Install — registering the Static Files scope

This directory holds the reference OpenTofu/Terraform used to **install** the
Static Files scope on a nullplatform account (registering its scope definition,
provider specification and scope configuration).

## Layout

```
install/
├── README.md            (this file)
├── aws/                 Working example for AWS (S3 + CloudFront + Route 53 + ACM)
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
└── azure/               Working example for Azure (Blob + CDN + Azure DNS)
    ├── main.tf
    ├── provider.tf
    ├── variables.tf
    ├── versions.tf
    └── terraform.tfvars.example
```

## Currently provided

- **AWS** (`aws/`) — complete working example. See
  [`../README.md`](../../README.md#registering-and-using-the-scope) for the
  full installation walkthrough, pre-requisites, and agent IAM guidance.

- **Azure** (`azure/`) — complete working example (Blob static website + CDN +
  Azure DNS). Mirrors the shape of `aws/`: same `scope_definition` and
  `scope_definition_agent_association` module calls, and a
  `nullplatform_provider_config` whose `attributes` carry the `azure_*` fields
  of the [`../scope-configuration.json.tpl`](../scope-configuration.json.tpl)
  schema. What varies per entry in `provider_configs` is the NRN, the resource
  group and the DNS zone; the OpenTofu state storage account is shared, the same
  way `aws_state_bucket` is on AWS.

  **Known limitation:** publishing the frontend bundle to a blob container is
  not covered by this example. The distribution layer derives the storage
  account from the asset URL and expects
  `https://<storage>.blob.core.windows.net/<container>/...`, and nothing on the
  platform produces such a URL today — the only provider specifications that
  take the asset-repository role are `ecr` and `docker-server`, both
  container-registry shaped. So an Azure install can register the scope and
  create scopes, but cannot yet complete a deployment. See
  [`../../README.md`](../../README.md) for the full explanation.

## Not yet provided

- **GCP** — the scope's layered architecture anticipates GCP as a third
  provider (see the layer diagram in [`../../README.md`](../../README.md)),
  but neither the scope nor this example has landed GCP support yet.

## Using an example (install the scope)

Replace `aws` with `azure` to install on Azure:

```bash
cp -r static-files/specs/install/aws /path/to/your/infra/scopes/static-files
cd /path/to/your/infra/scopes/static-files
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

tofu init
tofu apply
```

The variables and pre-requisites each example assumes are documented
in the top-level [`static-files/README.md`](../../README.md) under the
"Registering and Using the Scope" section.
