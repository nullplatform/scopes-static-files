locals {
  scope_definition = {
    git_repo       = "nullplatform/scopes-static-files"
    git_ref        = "main"
    git_scope_path = "static-files"
    name           = "Static Files"
    description    = "Allows you to deploy static files applications"
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
}

module "scope_definition" {
  source = "git::https://github.com/nullplatform/main-terraform-modules.git//modules/nullplatform/scope-definition?ref=main"

  nrn        = var.nrn
  np_api_key = var.np_api_key

  github_repo_url   = "https://${var.github_token}@github.com/${local.scope_definition.git_repo}"
  github_ref        = local.scope_definition.git_ref
  github_scope_path = local.scope_definition.git_scope_path
  scope_name        = local.scope_definition.name
  scope_description = local.scope_definition.description

  action_spec_names = local.scope_definition.actions

  organization_nrn          = var.organization_nrn
  create_scope_configuration = true
}

module "scope_definition_agent_association" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=main"

  api_key                  = var.np_api_key
  nrn                      = var.nrn
  scope_specification_id   = module.scope_definition.service_specification_id
  scope_specification_slug = module.scope_definition.service_specification_slug
  tags_selectors           = var.tags

  repository_notification_channel        = "https://${var.github_token}@raw.githubusercontent.com/${local.scope_definition.git_repo}/refs/heads"
  repository_notification_channel_branch = local.scope_definition.git_ref
  service_path                           = local.scope_definition.git_scope_path
  repo_path                              = "/root/.np/${local.scope_definition.git_repo}"
}

resource "nullplatform_provider_config" "static_files_configuration" {
  nrn = var.nrn

  type       = module.scope_definition.provider_specification_id
  dimensions = {}

  attributes = jsonencode({
    region = "us-east-1"
  })
}
