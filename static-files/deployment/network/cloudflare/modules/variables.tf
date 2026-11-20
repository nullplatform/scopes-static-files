variable "network_cloudflare_zone_id" {
  description = "Cloudflare zone ID the record is written into"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.network_cloudflare_zone_id))
    error_message = "network_cloudflare_zone_id must be a Cloudflare zone ID: 32 hexadecimal characters."
  }
}

variable "network_domain" {
  description = "Root domain name (e.g., example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.network_domain))
    error_message = "network_domain must be a hostname (e.g., example.com)."
  }
}

variable "network_subdomain" {
  description = "Subdomain prefix (e.g., 'app' for app.example.com, empty string for apex)"
  type        = string
  default     = ""
}

variable "network_cloudflare_proxied" {
  description = "Route the record through Cloudflare's proxy. Off by default: the distribution already terminates TLS and caches, and proxying it needs the zone's SSL mode set to Full."
  type        = bool
  default     = false
}
