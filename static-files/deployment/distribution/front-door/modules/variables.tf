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
