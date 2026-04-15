# Terraform example — registering the Static Files scope

This directory holds reference Terraform for registering the Static Files
scope on a nullplatform account.

## Layout

```
terraform/
├── README.md            (this file)
└── aws/                 Working example for AWS (S3 + CloudFront + Route 53 + ACM)
    ├── main.tf
    ├── variables.tf
    └── terraform.tfvars.example
```

## Currently provided

- **AWS** (`aws/`) — complete working example. See
  [`../README.md`](../../README.md#registering-and-using-the-scope) for the
  full installation walkthrough, pre-requisites, and agent IAM guidance.

## Not yet provided

- **Azure** — the scope itself supports Azure (see the `cloud_provider` selector
  in [`../scope-configuration.json.tpl`](../scope-configuration.json.tpl) and
  the `azure_*` provider / network / distribution fields in its schema). A
  reference Terraform wiring for Azure would mirror the shape of `aws/`:
  a `scope_definition` module call plus a `nullplatform_provider_config` with
  Azure-specific `attributes` (`azure_subscription_id`, `azure_resource_group`,
  `azure_state_storage_account`, `azure_state_container`, and the equivalents
  for the `network` and `distribution` layers). Contributions welcome —
  file a PR adding a sibling `azure/` directory with the same file layout.

- **GCP** — the scope's layered architecture anticipates GCP as a third
  provider (see the layer diagram in [`../../README.md`](../../README.md)),
  but neither the scope nor this example has landed GCP support yet.

## Using the AWS example

```bash
cp -r static-files/specs/terraform/aws /path/to/your/infra/scopes/static-files
cd /path/to/your/infra/scopes/static-files
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

tofu init
tofu apply
```

The variables and pre-requisites the AWS example assumes are documented
in the top-level [`static-files/README.md`](../../README.md) under the
"Registering and Using the Scope" section.
