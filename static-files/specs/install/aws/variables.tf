variable "nrn" {
  description = "NullPlatform Resource Name for the scope"
  type        = string
}

variable "np_api_key" {
  description = "nullplatform API key for authentication"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Map of tags used to select and filter channels and agents"
  type        = map(string)
}

# ------------------------------------------------------------------------------
# AWS provider-config attributes
#
# These feed into `nullplatform_provider_config.static_files_configuration`.
# Required for any scope of type Static Files that targets AWS. See
# `scope-configuration.json.tpl` for the full schema and `README.md` for the
# list of pre-requisites each of these assumes exists.
# ------------------------------------------------------------------------------

variable "aws_state_bucket" {
  description = <<-EOT
    S3 bucket for OpenTofu state. The nullplatform agent writes one state file
    per scope into this bucket during the deployment workflow. Shared across
    every `provider_configs` entry — the state bucket is a single bucket, not
    per-environment. Must exist before any scope is created; the agent's IAM
    role needs s3:GetObject / PutObject / DeleteObject / ListBucket on it.
  EOT
  type        = string
}

variable "provider_configs" {
  description = <<-EOT
    One entry per environment/region. Each element creates its own
    `nullplatform_provider_config` resource, typically scoped to a different
    NRN (e.g. per environment) with its own AWS region and DNS zone. The `nrn`
    of each entry is used as the `for_each` key, so keep it stable to avoid
    recreating provider configs on unrelated changes.

    `aws_network` picks where the scope writes its DNS record:
      - "route53" (default): set `aws_hosted_public_zone_id`.
      - "cloudflare": set `cloudflare_zone_id`. `cloudflare_proxied` is
        optional (default false). The API token is not configured here: the
        scope's worker reads it from the CLOUDFLARE_API_TOKEN environment
        variable.
  EOT
  type = list(object({
    nrn                       = string
    aws_region                = string
    aws_network               = optional(string, "route53")
    aws_hosted_public_zone_id = optional(string)
    cloudflare_zone_id        = optional(string)
    cloudflare_proxied        = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for cfg in var.provider_configs : contains(["route53", "cloudflare"], cfg.aws_network)
    ])
    error_message = "aws_network must be \"route53\" or \"cloudflare\"."
  }

  validation {
    condition = alltrue([
      for cfg in var.provider_configs :
      cfg.aws_network != "route53" || try(length(cfg.aws_hosted_public_zone_id) > 0, false)
    ])
    error_message = "aws_hosted_public_zone_id is required when aws_network is \"route53\"."
  }

  validation {
    condition = alltrue([
      for cfg in var.provider_configs :
      cfg.aws_network != "cloudflare" || can(regex("^[0-9a-f]{32}$", cfg.cloudflare_zone_id))
    ])
    error_message = "cloudflare_zone_id (32 hexadecimal characters) is required when aws_network is \"cloudflare\"."
  }
}
