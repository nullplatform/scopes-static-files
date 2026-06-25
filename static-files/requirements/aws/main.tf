module "service_infrastructure" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_infrastructure/aws?ref=feat/service-infrastructure-aws"

  service_name              = var.bucket_name
  oidc_provider_arn         = var.oidc_provider_arn
  oidc_provider_url         = var.oidc_provider_url
  service_account_name      = var.service_account_name
  service_account_namespace = var.service_account_namespace
  create_s3                 = true
  bucket_name               = var.bucket_name
}
