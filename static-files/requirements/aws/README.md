# requirements/aws

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
  source = "git::https://github.com/nullplatform/scopes-static-files.git//static-files/requirements/aws?ref=<tag>"

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

## Outputs

`permissions_role_arn`, `permissions_role_name`, `permissions_role_id`.

## Versioning

Point the module `source` at a **tag**, never a branch:

```hcl
?ref=v0.2.0   # ✅ immutable
?ref=main     # ⚠️ moves with every push
```
