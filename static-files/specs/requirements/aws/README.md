# specs/requirements/aws

AWS IAM the static-files scope needs to operate under the **assume-role** pattern,
consumed as an OpenTofu module by the implementation stack (same shape as the
`k8s` and `lambda` scope requirements).

It creates a dedicated **permissions role** that the nullplatform agent assumes
(`sts:AssumeRole`) plus the static-files permissions policy (S3, CloudFront, ACM,
Route53, WAF, Lambda@Edge). The role's ARN is wired into the agent
(`assume_role_arns`) and published to the AWS IAM provider under selector
`static-files`; at runtime `utils/assume_role_step` resolves it and assumes the role.

## Usage

```hcl
module "scope_requirements_static" {
  source = "git::https://github.com/nullplatform/scopes-static-files.git//static-files/specs/requirements/aws?ref=<tag>"

  cluster_name   = "aws-services-cluster"
  agent_role_arn = "arn:aws:iam::<account>:role/nullplatform-<cluster>-agent-role"
}
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | (required) | Cluster name; derives default resource names. |
| `agent_role_arn` | `""` → derived | Agent role trusted to assume this role. Empty derives `nullplatform-<cluster>-agent-role`. |
| `additional_agent_role_arns` | `[]` | Extra trusted principals. |
| `role_name` | `""` → `nullplatform_<cluster>_static_scopes_role` | Override for the role name. |
| `policies_name_prefix` | `""` → `nullplatform_<cluster>` | Override for the policy name prefix. |
| `iam_create_role` | `true` | When false, the module creates nothing. |
| `iam_resource_tags_json` | `{}` | Tags applied to IAM resources. |
| `assets_bucket_arn` | `""` | ARN of the assets bucket (frontend bundles pre-requisite). When set, emits `cloudfront_oac_bucket_policy_json`. Leave empty to skip. |

## Outputs

`permissions_role_arn`, `permissions_role_name`, `permissions_role_id`, `cloudfront_oac_bucket_policy_json`.

### Assets bucket policy statement

The static-files scope validates — but never writes — a bucket policy on the
assets bucket granting `cloudfront.amazonaws.com` read access via Origin
Access Control (OAC). That statement has a history of disappearing after a
CloudFront distribution replacement when it's maintained by hand,
disconnected from any module.

This module does **not** create an `aws_s3_bucket_policy` resource — a bucket
can only be managed by one such resource, and the assets bucket's policy
resource almost always already exists (created alongside the bucket).
Instead, set `assets_bucket_arn` and merge the resulting
`cloudfront_oac_bucket_policy_json` output into the policy document that
feeds your existing `aws_s3_bucket_policy`:

```hcl
module "scope_requirements_static" {
  source = "git::https://github.com/nullplatform/scopes-static-files.git//static-files/specs/requirements/aws?ref=<tag>"

  cluster_name      = "aws-services-cluster"
  agent_role_arn    = "arn:aws:iam::<account>:role/nullplatform-<cluster>-agent-role"
  assets_bucket_arn = module.assets_bucket.bucket_arn
}

data "aws_iam_policy_document" "assets_bucket" {
  source_policy_documents = [
    module.scope_requirements_static.cloudfront_oac_bucket_policy_json,
    # ... your existing statements (e.g. DenyNonSecureTransport) ...
  ]
}

resource "aws_s3_bucket_policy" "assets_bucket" {
  bucket = module.assets_bucket.bucket_name
  policy = data.aws_iam_policy_document.assets_bucket.json
}
```

## Versioning

Point the module `source` at a **tag**, never a branch:

```hcl
?ref=v0.2.0   # ✅ immutable
?ref=main     # ⚠️ moves with every push
```
