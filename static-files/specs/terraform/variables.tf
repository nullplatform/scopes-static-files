variable "nrn" {
  description = "NullPlatform Resource Name for the scope"
  type        = string
}

variable "np_api_key" {
  description = "nullplatform API key for authentication"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub personal access token for accessing private repos"
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

variable "aws_region" {
  description = "AWS region where scope resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "aws_state_bucket" {
  description = <<-EOT
    S3 bucket for per-scope OpenTofu state. The nullplatform agent writes one
    state file per scope into this bucket during the deployment workflow. Must
    exist before any scope is created; the agent's IAM role needs
    s3:GetObject / PutObject / DeleteObject / ListBucket on it.
  EOT
  type        = string
}

variable "aws_hosted_public_zone_id" {
  description = <<-EOT
    Route 53 public hosted zone ID where per-scope DNS records are created
    (e.g. `Z012209428HPFIKB27ZR`). The zone must already exist; the scope only
    writes records into it.
  EOT
  type        = string
}
