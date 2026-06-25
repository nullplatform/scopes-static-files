output "role_arn" {
  description = "ARN of the IRSA IAM role"
  value       = module.irsa.role_arn
}

output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.static_files.bucket
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.static_files.arn
}
