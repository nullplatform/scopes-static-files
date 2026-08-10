output "permissions_role_arn" {
  description = "ARN of the static-files permissions role assumed by the nullplatform agent role. Pass to the agent (assume_role_arns) and publish to the AWS IAM provider (selector \"static-files\")."
  value       = local.iam_create ? aws_iam_role.nullplatform_static_files[0].arn : ""
}

output "permissions_role_name" {
  description = "Name of the static-files permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_static_files[0].name : ""
}

output "permissions_role_id" {
  description = "ID of the static-files permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_static_files[0].id : ""
}

output "cloudfront_oac_bucket_policy_json" {
  description = "IAM policy document (JSON) with the AllowCloudFrontOACRead statement for the assets bucket, or \"\" when assets_bucket_arn is not set. Merge this into the aws_iam_policy_document that feeds the aws_s3_bucket_policy already managing the assets bucket, e.g.: data \"aws_iam_policy_document\" \"assets_bucket\" { source_policy_documents = [module.scope_requirements_static.cloudfront_oac_bucket_policy_json, <your existing statements>] }. Do not attach this output directly as a second aws_s3_bucket_policy resource on the same bucket."
  value       = var.assets_bucket_arn != "" ? data.aws_iam_policy_document.cloudfront_oac_read[0].json : ""
}
