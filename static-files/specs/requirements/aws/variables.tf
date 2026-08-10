variable "agent_role_arn" {
  description = "ARN of the primary nullplatform agent IRSA role allowed to assume this permissions role via sts:AssumeRole, and always a trusted principal of the role's trust policy. Defaults (when empty) to the conventional agent role for the cluster: arn:aws:iam::<account>:role/nullplatform-<cluster_name>-agent-role."
  type        = string
  default     = ""

  validation {
    condition     = var.agent_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.agent_role_arn))
    error_message = "agent_role_arn must be empty (to use the derived default) or match arn:aws:iam::<account-id>:role/<role-name>"
  }
}

variable "additional_agent_role_arns" {
  description = "Extra IAM role ARNs allowed to assume this permissions role, appended to agent_role_arn in the trust policy. Defaults to none."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.additional_agent_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", arn))])
    error_message = "each additional_agent_role_arns entry must match arn:aws:iam::<account-id>:role/<role-name>"
  }
}

variable "cluster_name" {
  description = "Name of the cluster where the agent runs. Used to derive default resource names."
  type        = string
}

variable "role_name" {
  description = "Override for the static-files permissions IAM role name. Defaults to nullplatform_{cluster_name}_static_scopes_role."
  type        = string
  default     = ""
}

variable "policies_name_prefix" {
  description = "Override for the IAM policy name prefix. Defaults to nullplatform_{cluster_name}."
  type        = string
  default     = ""
}

variable "iam_create_role" {
  description = "Whether to create the permissions role and its policy. When false, the module produces no resources."
  type        = bool
  default     = true
}

variable "iam_resource_tags_json" {
  description = "Tags to apply to IAM resources created by this module."
  type        = map(string)
  default     = {}
}

variable "assets_bucket_arn" {
  description = "ARN of the S3 bucket that stores frontend bundles (the static-files 'assets bucket' pre-requisite). When set, the module outputs a ready-to-merge IAM policy document statement granting the CloudFront distribution's Origin Access Control (OAC) read access to this bucket. This module does NOT create an aws_s3_bucket_policy resource itself — merge the output into whichever module already owns that bucket's policy (a bucket can only have one aws_s3_bucket_policy resource managing it). Leave empty to skip generating the statement."
  type        = string
  default     = ""

  validation {
    condition     = var.assets_bucket_arn == "" || can(regex("^arn:aws:s3:::.+", var.assets_bucket_arn))
    error_message = "assets_bucket_arn must be empty or match arn:aws:s3:::<bucket-name>"
  }
}
