################################################################################
# Static-files scope — assume-role IAM
#
# The static-files scope operates AWS (S3, CloudFront, ACM, Route53, WAF,
# Lambda@Edge) via the ASSUME-ROLE pattern: this dedicated role holds the
# permissions and the nullplatform agent assumes it (sts:AssumeRole). The
# consuming stack passes this role's ARN to the agent (assume_role_arns) and
# publishes it to the nullplatform AWS IAM provider (selector "static-files").
#
# The role trusts the agent role BY NAME (derived default) rather than by a
# module output, so the consuming stack can wire the ARN back into the agent
# without creating a dependency cycle. The agent role name is the conventional
# "nullplatform-{cluster_name}-agent-role".
################################################################################

resource "aws_iam_role" "nullplatform_static_files" {
  count = local.iam_create ? 1 : 0

  name        = local.role_name
  description = "Permissions role assumed by the nullplatform agent role for the static-files scope"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = concat([local.agent_role_arn], var.additional_agent_role_arns) }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.iam_default_tags
}

# Static scopes permissions: S3, CloudFront, ACM, Route53, WAF, Lambda@Edge.
resource "aws_iam_policy" "nullplatform_static_files" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_static_files_policy"
  description = "Policy for the static-files scope (S3, CloudFront, ACM, Route53, WAF, Lambda@Edge)"
  tags        = local.iam_default_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StaticAssets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFrontDistribution"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:ListTagsForResource",
          "cloudfront:CreateInvalidation",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl"
        ]
        Resource = "*"
      },
      {
        Sid    = "ACMCertificates"
        Effect = "Allow"
        Action = [
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "acm:GetCertificate",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53DNS"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Sid    = "WAFv2WebACLLookup"
        Effect = "Allow"
        Action = [
          "wafv2:ListWebACLs",
          "wafv2:GetWebACL"
        ]
        Resource = "arn:aws:wafv2:us-east-1:*:global/webacl/*/*"
      },
      {
        # Lambda@Edge function associations on CloudFront cache behaviors.
        # CloudFront validates these permissions for the caller when
        # creating/updating a distribution that references a Lambda@Edge function.
        Sid    = "LambdaEdgeAssociation"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:EnableReplication*"
        ]
        Resource = "arn:aws:lambda:us-east-1:*:function:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "static_files" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_static_files[0].name
  policy_arn = aws_iam_policy.nullplatform_static_files[0].arn
}
