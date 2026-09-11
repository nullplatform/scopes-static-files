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

variable "distribution_default_behavior" {
  description = <<-EOT
    Default cache behavior: the one that serves every request no path pattern matches.
    Caching is expressed with CloudFront cache policies, by name (managed policies included)
    or by id. Invocations are one field per event type: CloudFront accepts a single
    Lambda@Edge per event type and a single CloudFront Function per viewer event.
  EOT
  type = object({
    cache_policy             = optional(string)
    cache_policy_id          = optional(string)
    origin_request_policy    = optional(string)
    response_headers_policy  = optional(string)
    allowed_methods          = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods           = optional(list(string), ["GET", "HEAD"])
    viewer_protocol_policy   = optional(string, "redirect-to-https")
    compress                 = optional(bool, true)
    lambda_viewer_request    = optional(string)
    lambda_viewer_response   = optional(string)
    lambda_origin_request    = optional(string)
    lambda_origin_response   = optional(string)
    function_viewer_request  = optional(string)
    function_viewer_response = optional(string)
  })
  default = {}

  validation {
    condition = alltrue([
      for arn in [
        var.distribution_default_behavior.lambda_viewer_request,
        var.distribution_default_behavior.lambda_viewer_response,
        var.distribution_default_behavior.lambda_origin_request,
        var.distribution_default_behavior.lambda_origin_response,
      ] : arn == null || can(regex(":[0-9]+$", coalesce(arn, "")))
    ])
    error_message = "Lambda@Edge ARNs must include a published version (they cannot point at $LATEST or an alias)."
  }

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.distribution_default_behavior.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be one of: allow-all, https-only, redirect-to-https."
  }

  validation {
    condition     = !(var.distribution_default_behavior.cache_policy_id != null && var.distribution_default_behavior.cache_policy != null)
    error_message = "Set either cache_policy (by name) or cache_policy_id, not both."
  }
}

variable "distribution_behaviors" {
  description = <<-EOT
    Ordered cache behaviors, one per path pattern. The list order is the CloudFront
    precedence: the first pattern that matches a request wins. Same shape as
    distribution_default_behavior plus the required path_pattern.
  EOT
  type = list(object({
    path_pattern             = string
    cache_policy             = optional(string)
    cache_policy_id          = optional(string)
    origin_request_policy    = optional(string)
    response_headers_policy  = optional(string)
    allowed_methods          = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods           = optional(list(string), ["GET", "HEAD"])
    viewer_protocol_policy   = optional(string, "redirect-to-https")
    compress                 = optional(bool, true)
    lambda_viewer_request    = optional(string)
    lambda_viewer_response   = optional(string)
    lambda_origin_request    = optional(string)
    lambda_origin_response   = optional(string)
    function_viewer_request  = optional(string)
    function_viewer_response = optional(string)
  }))
  default = []

  validation {
    condition     = length(distinct([for b in var.distribution_behaviors : b.path_pattern])) == length(var.distribution_behaviors)
    error_message = "Each behavior needs its own path_pattern: CloudFront rejects duplicates."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.distribution_behaviors : [
        for arn in [b.lambda_viewer_request, b.lambda_viewer_response, b.lambda_origin_request, b.lambda_origin_response] :
        arn == null || can(regex(":[0-9]+$", coalesce(arn, "")))
      ]
    ]))
    error_message = "Lambda@Edge ARNs must include a published version (they cannot point at $LATEST or an alias)."
  }

  validation {
    condition = alltrue([
      for b in var.distribution_behaviors : contains(["allow-all", "https-only", "redirect-to-https"], b.viewer_protocol_policy)
    ])
    error_message = "viewer_protocol_policy must be one of: allow-all, https-only, redirect-to-https."
  }

  validation {
    condition = alltrue([
      for b in var.distribution_behaviors :
      !(b.cache_policy_id != null && b.cache_policy != null)
    ])
    error_message = "Set either cache_policy (by name) or cache_policy_id on a behavior, not both."
  }
}

variable "distribution_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.distribution_price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "distribution_default_root_object" {
  description = "Object CloudFront returns when the request is for the distribution root"
  type        = string
  default     = "index.html"
}

variable "distribution_geo_restriction" {
  description = "Geographic restriction applied to the distribution"
  type = object({
    restriction_type = optional(string, "none")
    locations        = optional(list(string), [])
  })
  default = {}
}

variable "distribution_custom_error_responses" {
  description = <<-EOT
    Custom error responses. SPAs usually map 403 and 404 to /index.html with a 200
    response code; other apps want the original status, so nothing is created unless
    it is configured here.
  EOT
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
  default = []
}
