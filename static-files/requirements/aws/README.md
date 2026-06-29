# requirements/aws

This directory declares the AWS infrastructure the scope needs to operate. It is consumed by `tofu-modules` as an OpenTofu module at `tofu apply` time.

## How it works

`tofu-modules` references this directory as a git module source:

```hcl
module "static_scope_infrastructure" {
  source = "git::github.com/nullplatform/<scope-repo>.git//requirements/aws?ref=<tag>"

  bucket_name    = "..."
  service_name   = "..."
  agent_role_arn = "..."
}
```

OpenTofu clones the repository, loads this directory as a module, and applies the declared resources into the customer's infrastructure state.

## Required variables

| Variable | Description |
|---|---|
| `bucket_name` | Name of the S3 bucket to create |
| `service_name` | Prefix used to name the IAM role and policies |
| `agent_role_arn` | ARN of the nullplatform agent IAM role |

## Requirements

### IAM Role is mandatory

**Every scope that declares infrastructure in this directory must create an IAM role** that allows the nullplatform agent to assume the credentials needed to operate the resources.

The role must have a trust policy that allows the agent role to assume it via `sts:AssumeRole`:

```hcl
resource "aws_iam_role" "this" {
  name = "${var.service_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.agent_role_arn }
    }]
  })
}
```

Without this role the agent cannot access any of the resources declared in this directory.

## Versioning

The module `source` must always point to a **tag**, never to a branch:

```hcl
# ✅ Correct — immutable
?ref=v1.0.0

# ❌ Incorrect — any push to the branch changes what gets applied
?ref=feat/my-branch
```
