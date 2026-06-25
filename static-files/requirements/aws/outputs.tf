output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.static_files.bucket
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.static_files.arn
}

output "role_arn" {
  description = "ARN of the IAM role with S3 access (for IRSA annotation)"
  value       = module.irsa_role.role_arn
}
