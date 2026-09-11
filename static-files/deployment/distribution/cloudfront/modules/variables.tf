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

# =============================================================================
# Cache behaviors
#
# Caching itself is not configurable: every behavior forwards nothing to the
# origin and keeps the same TTLs the scope has always used. What a behavior
# does carry is how it answers the viewer, whether it compresses, and the
# functions it runs.
#
# An invocation names the kind of function and the event in one string, the way
# the scope configuration offers it: "Lambda@Edge - viewer request".
# =============================================================================
variable "distribution_default_behavior" {
  description = "Behavior serving every request no path pattern matches. CloudFront always requires it."
  type = object({
    viewer_protocol_policy = optional(string, "redirect-to-https")
    compress               = optional(bool, true)
    invocations = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
  })
  default = {}

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.distribution_default_behavior.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be one of: allow-all, https-only, redirect-to-https."
  }

  validation {
    condition = alltrue([
      for i in var.distribution_default_behavior.invocations :
      contains([
        "CloudFront Function - viewer request", "CloudFront Function - viewer response",
        "Lambda@Edge - viewer request", "Lambda@Edge - viewer response",
        "Lambda@Edge - origin request", "Lambda@Edge - origin response",
      ], i.event_type)
    ])
    error_message = "Each invocation must name a function kind and an event CloudFront accepts, e.g. 'Lambda@Edge - viewer request'. CloudFront Functions run on viewer events only."
  }

  validation {
    condition = alltrue([
      for i in var.distribution_default_behavior.invocations :
      startswith(i.event_type, "Lambda@Edge") ? can(regex(":[0-9]+$", i.function_arn)) : true
    ])
    error_message = "Lambda@Edge ARNs must include a published version (they cannot point at $LATEST or an alias)."
  }

  validation {
    condition     = length(distinct([for i in var.distribution_default_behavior.invocations : i.event_type])) == length(var.distribution_default_behavior.invocations)
    error_message = "CloudFront runs a single function per event: each invocation of a behavior needs its own event."
  }
}

variable "distribution_behaviors" {
  description = <<-EOT
    Ordered cache behaviors, one per path pattern. The list order is the
    CloudFront precedence: the first pattern that matches a request wins.
  EOT
  type = list(object({
    path_pattern           = string
    viewer_protocol_policy = optional(string, "redirect-to-https")
    compress               = optional(bool, true)
    invocations = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for b in var.distribution_behaviors : b.path_pattern])) == length(var.distribution_behaviors)
    error_message = "Each behavior needs its own path_pattern: CloudFront rejects duplicates."
  }

  validation {
    condition = alltrue([
      for b in var.distribution_behaviors : contains(["allow-all", "https-only", "redirect-to-https"], b.viewer_protocol_policy)
    ])
    error_message = "viewer_protocol_policy must be one of: allow-all, https-only, redirect-to-https."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.distribution_behaviors : [
        for i in b.invocations : contains([
          "CloudFront Function - viewer request", "CloudFront Function - viewer response",
          "Lambda@Edge - viewer request", "Lambda@Edge - viewer response",
          "Lambda@Edge - origin request", "Lambda@Edge - origin response",
        ], i.event_type)
      ]
    ]))
    error_message = "Each invocation must name a function kind and an event CloudFront accepts, e.g. 'Lambda@Edge - viewer request'. CloudFront Functions run on viewer events only."
  }

  validation {
    condition = alltrue(flatten([
      for b in var.distribution_behaviors : [
        for i in b.invocations :
        startswith(i.event_type, "Lambda@Edge") ? can(regex(":[0-9]+$", i.function_arn)) : true
      ]
    ]))
    error_message = "Lambda@Edge ARNs must include a published version (they cannot point at $LATEST or an alias)."
  }

  validation {
    condition = alltrue([
      for b in var.distribution_behaviors :
      length(distinct([for i in b.invocations : i.event_type])) == length(b.invocations)
    ])
    error_message = "CloudFront runs a single function per event: each invocation of a behavior needs its own event."
  }
}

# =============================================================================
# Distribution-wide settings
# =============================================================================
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
