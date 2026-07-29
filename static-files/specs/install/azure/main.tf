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

  repository_base_url = "https://raw.githubusercontent.com/${local.scope_definition.repository_service_spec}/refs/heads"
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

  repository_notification_channel        = "https://raw.githubusercontent.com/${local.scope_definition.repository_service_spec}/refs/heads"
  repository_notification_channel_branch = local.scope_definition.repository_service_spec_branch
  service_path                           = local.scope_definition.service_path
  repo_path                              = "/root/.np/${local.scope_definition.repository_service_spec}"
}

# ------------------------------------------------------------------------------
# Provider configuration for scopes of type Static Files.
#
# One `nullplatform_provider_config` per entry in `var.provider_configs`, typically
# one entry per environment (dev/stg/prd) with its own NRN, subscription, resource
# group, and Azure DNS zone. The OpenTofu state storage account
# (`var.azure_state_storage_account` / `var.azure_state_container`) is shared across
# all entries — there is exactly one state location, regardless of how many
# environments you configure.
#
# The `nrn` of each entry is used as the `for_each` key so that adding or
# removing an environment does not reorder the other resources in state.
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
# "network layer is not configured for provider 'azure'". The API does not
# validate attributes against the schema at create time, so the problem is
# only surfaced on the first deployment attempt.
# ------------------------------------------------------------------------------
resource "nullplatform_provider_config" "static_files_configuration" {
  for_each = { for cfg in var.provider_configs : cfg.nrn => cfg }

  nrn = each.value.nrn

  type       = module.scope_definition.provider_specification_slug
  dimensions = {}

  attributes = jsonencode({
    cloud_provider = "azure"

    provider = {
      azure_subscription_id       = coalesce(each.value.azure_subscription_id, var.azure_subscription_id)
      azure_resource_group        = each.value.azure_resource_group
      azure_state_storage_account = var.azure_state_storage_account
      azure_state_container       = var.azure_state_container
    }

    network = {
      azure_network       = "azure_dns"
      azure_dns_zone_name = each.value.azure_dns_zone_name

      # Must equal the scope's resource group: `network/azure_dns/setup` preflight-checks
      # this value but never forwards it, and the module resolves the zone against
      # `azure_provider.resource_group`. Pointing it elsewhere passes the preflight and
      # then reads the wrong resource group, so it is not exposed as a variable.
      azure_dns_zone_resource_group = each.value.azure_resource_group
    }

    distribution = {
      azure_distribution = "blob-cdn"
    }
  })
}
