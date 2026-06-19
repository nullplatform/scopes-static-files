variable "distribution_bucket_name" {
  description = "Existing S3 bucket name for static website distribution"
  type        = string
}

variable "distribution_s3_prefix" {
  description = "S3 prefix/path for this scope's files (e.g., 'app-name/scope-id')"
  type        = string
}

variable "distribution_app_name" {
  description = "Application name (used for resource naming)"
  type        = string
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}

variable "distribution_cloudfront_endpoint_url" {
  description = "Custom CloudFront endpoint URL for AWS CLI (used for testing with moto)"
  type        = string
  default     = ""
}

variable "distribution_lambda_associations" {
  description = "Lambda@Edge function associations for the default cache behavior. Each lambda_arn must include a published version and the function must live in us-east-1."
  type = list(object({
    event_type   = string
    function_arn = string
  }))
  default = []
}