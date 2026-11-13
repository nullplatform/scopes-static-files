locals {
  # Module identifier
  iam_module_name = "requirements-static-files"

  # Whether resources are created
  iam_create = var.iam_create_role

  # Derived names (overridable via variables). Uses the static_files naming
  # consistently: role nullplatform_<cluster>_static_files_role and policy
  # nullplatform_<cluster>_static_files_policy.
  role_name            = var.role_name != "" ? var.role_name : "nullplatform_${var.cluster_name}_static_files_role"
  policies_name_prefix = var.policies_name_prefix != "" ? var.policies_name_prefix : "nullplatform_${var.cluster_name}"

  # Primary agent role trusted by the permissions role. Defaults to the
  # conventional agent role name for the cluster when not provided explicitly.
  agent_role_arn = var.agent_role_arn != "" ? var.agent_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nullplatform-${var.cluster_name}-agent-role"

  # Must match the tf_state_key prefix in deployment/scripts/build_context; the
  # S3 lock file (<key>.tflock) lives under it too.
  state_key_prefix = "nullplatform/scopes/static-files/"

  # Setting state_bucket_arn opts into scoped S3 access: the scope reads the assets
  # bucket (never its objects) and reads, writes and deletes its own state. Without
  # it the role keeps these actions on every bucket, as before.
  s3_scoped = var.state_bucket_arn != ""
  # A path in assets_bucket_arn is reduced to its bucket: bucket reads need the bucket ARN.
  assets_bucket_resources = var.assets_bucket_arn != "" ? [split("/", var.assets_bucket_arn)[0]] : ["*"]

  s3_statements = local.s3_scoped ? [
    {
      Sid      = "S3AssetsBucketRead"
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketPolicy"]
      Resource = local.assets_bucket_resources
    },
    {
      Sid      = "S3StateBucketList"
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = [var.state_bucket_arn]
    },
    {
      Sid      = "S3StateObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = ["${var.state_bucket_arn}/${local.state_key_prefix}*"]
    },
    ] : [
    {
      Sid      = "S3StaticAssets"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketPolicy"]
      Resource = ["*"]
    },
  ]

  # Default tags applied to every IAM resource
  iam_default_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "nullplatform-custom-scope-role"
    Module    = local.iam_module_name
  })
}
