module "irsa" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_infrastructure/aws?ref=feat/service-infrastructure-aws"

  service_name              = var.service_name
  oidc_provider_arn         = var.oidc_provider_arn
  oidc_provider_url         = var.oidc_provider_url
  service_account_name      = var.service_account_name
  service_account_namespace = var.service_account_namespace
}

resource "aws_s3_bucket" "static_files" {
  bucket = "${var.service_name}-static"
}

resource "aws_s3_bucket_versioning" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.static_files.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.static_files.arn}/*"]
  }
}

resource "aws_iam_policy" "s3" {
  name   = "${var.service_name}-s3-policy"
  policy = data.aws_iam_policy_document.s3.json
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = module.irsa.role_name
  policy_arn = aws_iam_policy.s3.arn
}
