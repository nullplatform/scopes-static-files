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

variable "organization_nrn" {
  description = "Organization NRN used to replace the NRN placeholder in scope-configuration.json.tpl"
  type        = string
}

variable "tags" {
  description = "Map of tags used to select and filter channels and agents"
  type        = map(string)
}

