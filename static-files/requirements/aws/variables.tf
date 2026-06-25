variable "service_name" {
  description = "Name prefix for all created IAM resources"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for the IRSA trust policy"
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
