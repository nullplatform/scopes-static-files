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
    NRN (e.g. per environment) with its own AWS region and Route 53 hosted
    zone. The `nrn` of each entry is used as the `for_each` key, so keep it
    stable to avoid recreating provider configs on unrelated changes.
  EOT
  type = list(object({
    nrn                       = string
    aws_region                = string
    aws_hosted_public_zone_id = string
  }))
}
