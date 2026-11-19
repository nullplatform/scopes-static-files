variable "network_cloudflare_zone_id" {
  description = "Cloudflare zone ID the record is written into"
  type        = string
}

variable "network_domain" {
  description = "Root domain name (e.g., example.com)"
  type        = string
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

variable "network_cloudflare_ttl" {
  description = "TTL of the record in seconds; 1 means automatic. Ignored (forced to 1) when the record is proxied."
  type        = number
  default     = 300
}
