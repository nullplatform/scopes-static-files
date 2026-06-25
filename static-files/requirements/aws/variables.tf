variable "role_name" {
  description = "Name of the IAM role to attach service-specific policies to"
  type        = string
}

variable "service_name" {
  description = "Name prefix for IAM policies created by this module"
  type        = string
}
