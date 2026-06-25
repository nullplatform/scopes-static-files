resource "aws_s3_bucket" "static_files" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "static_files_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"]
    }
  }
}

resource "aws_iam_role" "static_files" {
  name               = "${var.bucket_name}-static-files-role"
  assume_role_policy = data.aws_iam_policy_document.static_files_trust.json
}

data "aws_iam_policy_document" "static_files_s3" {
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

resource "aws_iam_policy" "static_files_s3" {
  name   = "${var.bucket_name}-static-files-policy"
  policy = data.aws_iam_policy_document.static_files_s3.json
}

resource "aws_iam_role_policy_attachment" "static_files_s3" {
  role       = aws_iam_role.static_files.name
  policy_arn = aws_iam_policy.static_files_s3.arn
}
