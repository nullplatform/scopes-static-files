# `np_api_key` also feeds the `np` CLI the modules shell out to, but that path
# does not configure this provider — without this block it falls back to the
# NULLPLATFORM_API_KEY environment variable and `tofu apply` fails to
# authenticate.
provider "nullplatform" {
  api_key = var.np_api_key
}
