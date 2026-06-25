variable "bucket_name" {
  description = "Name of the S3 bucket to create for static files storage"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (used for IRSA trust policy)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider without https:// prefix"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name that will assume the IAM role"
  type        = string
  default     = "nullplatform-agent"
}

variable "service_account_namespace" {
  description = "Kubernetes namespace of the service account"
  type        = string
  default     = "nullplatform"
}
