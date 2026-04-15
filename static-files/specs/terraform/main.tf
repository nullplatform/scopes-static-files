locals {
  scope_definition = {
    repository_service_spec        = "nullplatform/scopes-static-files"
    repository_service_spec_branch = "main"
    service_path                   = "static-files"
    name                           = "Static Files"
    description                    = "Allows you to deploy static files applications"
    actions = [
      "create-scope",
      "delete-scope",
      "start-initial",
      "start-blue-green",
      "finalize-blue-green",
      "rollback-deployment",
      "delete-deployment",
    ]
  }

  repository_base_url = "https://${var.github_token}@raw.githubusercontent.com/${local.scope_definition.repository_service_spec}/refs/heads"
}

module "scope_definition" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition?ref=main"

  nrn        = var.nrn
  np_api_key = var.np_api_key

  repository_service_spec            = local.repository_base_url
  repository_service_spec_branch     = local.scope_definition.repository_service_spec_branch
  repository_scope_template          = local.repository_base_url
  repository_scope_template_branch   = local.scope_definition.repository_service_spec_branch
  repository_action_templates        = local.repository_base_url
  repository_action_templates_branch = local.scope_definition.repository_service_spec_branch
  service_path                       = local.scope_definition.service_path
  service_spec_name                  = local.scope_definition.name
  service_spec_description           = local.scope_definition.description

  action_spec_names          = local.scope_definition.actions
  create_scope_configuration = true
}

module "scope_definition_agent_association" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=main"

  api_key                  = var.np_api_key
  nrn                      = var.nrn
  scope_specification_id   = module.scope_definition.service_specification_id
  scope_specification_slug = module.scope_definition.service_slug
  tags_selectors           = var.tags

  repository_notification_channel        = "https://${var.github_token}@raw.githubusercontent.com/${local.scope_definition.repository_service_spec}/refs/heads"
  repository_notification_channel_branch = local.scope_definition.repository_service_spec_branch
  service_path                           = local.scope_definition.service_path
  repo_path                              = "/root/.np/${local.scope_definition.repository_service_spec}"
}

# ------------------------------------------------------------------------------
# Provider configuration for scopes of type Static Files.
#
# IMPORTANT — about `type`: this field expects the provider specification *slug*,
# NOT its UUID. Using `module.scope_definition.provider_specification_id` (the
# UUID) silently fails at apply time with:
#
#   Error: error fetching specification ID for slug <UUID>:
#          no specification found for slug: <UUID>
#
# Always use `provider_specification_slug`.
#
# IMPORTANT — about `attributes`: the scope workflow validates all three layers
# (provider / network / distribution) at deployment time. If any of them is
# missing, `start-initial` rolls back with messages like
# "network layer is not configured for provider 'aws'". The API does not
# validate attributes against the schema at create time, so the problem is
# only surfaced on the first deployment attempt.
# ------------------------------------------------------------------------------
resource "nullplatform_provider_config" "static_files_configuration" {
  nrn = var.nrn

  type       = module.scope_definition.provider_specification_slug
  dimensions = {}

  attributes = jsonencode({
    cloud_provider = "aws"

    provider = {
      aws_region       = var.aws_region
      aws_state_bucket = var.aws_state_bucket
    }

    network = {
      aws_network               = "route53"
      aws_hosted_public_zone_id = var.aws_hosted_public_zone_id
    }

    distribution = {
      aws_distribution = "cloudfront"
    }
  })
}
