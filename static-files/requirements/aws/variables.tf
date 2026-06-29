variable "bucket_name" {
  description = "Name of the S3 bucket to create"
  type        = string
}

variable "service_name" {
  description = "Name prefix used for the IAM role and policies"
  type        = string
}

variable "agent_role_arn" {
  description = "ARN of the nullplatform agent IAM role allowed to assume the scope role"
  type        = string
}
