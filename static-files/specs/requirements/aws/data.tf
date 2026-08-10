data "aws_caller_identity" "current" {}

# CloudFront OAC read-access statement for the assets bucket.
#
# The static-files scope's cloudfront/setup validates (but never writes) a
# bucket policy on the assets bucket granting cloudfront.amazonaws.com
# s3:GetObject, scoped to this account via AWS:SourceAccount. That statement
# has repeatedly gone missing after a CloudFront distribution replacement
# because it lived only as a manually-maintained, disconnected policy.
#
# Exposed as a standalone IAM policy document (JSON) so it can be merged —
# via aws_iam_policy_document.source_policy_documents — into whichever
# resource already owns the assets bucket's aws_s3_bucket_policy. This module
# intentionally does not create that resource itself: a bucket can only be
# managed by one aws_s3_bucket_policy, and that resource almost always
# already exists (created alongside the bucket).
data "aws_iam_policy_document" "cloudfront_oac_read" {
  count = var.assets_bucket_arn != "" ? 1 : 0

  statement {
    sid    = "AllowCloudFrontOACRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${var.assets_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}
