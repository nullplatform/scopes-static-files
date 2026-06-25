output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = module.service_infrastructure.bucket_name
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = module.service_infrastructure.bucket_arn
}

output "role_arn" {
  description = "ARN of the IAM role with S3 access (for IRSA annotation)"
  value       = module.service_infrastructure.role_arn
}
