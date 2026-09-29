variable "distribution_storage_account" {
  description = "Azure Storage account that hosts the static website ($web) with the bundles"
  type        = string
}

variable "distribution_container_name" {
  description = "Blob container the asset URL points to (informational; the origin is the static-website host)"
  type        = string
  default     = "$web"
}

variable "distribution_blob_prefix" {
  description = "Blob path prefix for this scope's files (e.g. '/frontends/4/612605537')"
  type        = string
  default     = "/"
}

variable "distribution_app_name" {
  description = "Base name for every resource this scope creates (<app>-<scope>-<id>)"
  type        = string
}

variable "distribution_resource_tags_json" {
  description = "Resource tags as JSON object"
  type        = map(string)
  default     = {}
}

variable "distribution_front_door_profile" {
  description = "Name of the shared Front Door profile (customer-owned, read only)"
  type        = string
}

variable "distribution_front_door_endpoint" {
  description = "Name of the shared Front Door endpoint inside the profile (customer-owned, read only)"
  type        = string
}

variable "distribution_front_door_resource_group" {
  description = "Resource group that holds the shared Front Door profile"
  type        = string
}

variable "distribution_cached_path_prefixes" {
  description = "Path prefixes served with the long cache (StaticCache); every other path is never cached (NoCacheOutsideStatic)"
  type        = list(string)
  default     = ["/static/"]

  validation {
    condition     = length(var.distribution_cached_path_prefixes) >= 1 && length(var.distribution_cached_path_prefixes) <= 10
    error_message = "distribution_cached_path_prefixes must hold between 1 and 10 prefixes (a Front Door condition accepts at most 10 match values)."
  }

  validation {
    condition     = alltrue([for prefix in var.distribution_cached_path_prefixes : startswith(prefix, "/")])
    error_message = "Every entry in distribution_cached_path_prefixes must start with '/'."
  }
}

variable "distribution_cache_days" {
  description = "Days StaticCache keeps the files under the cached path prefixes at the edge"
  type        = number
  default     = 7

  validation {
    condition     = var.distribution_cache_days >= 1 && var.distribution_cache_days <= 365 && floor(var.distribution_cache_days) == var.distribution_cache_days
    error_message = "distribution_cache_days must be a whole number of days between 1 and 365."
  }
}
