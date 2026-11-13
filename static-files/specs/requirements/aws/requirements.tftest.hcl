# =============================================================================
# Unit tests for specs/requirements/aws
#
# Run: tofu init -backend=false && tofu test
# =============================================================================

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
}

variables {
  cluster_name = "test"
}

run "no_bucket_policy_writes" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement :
      !contains(flatten([s.Action]), "s3:PutBucketPolicy") && !contains(flatten([s.Action]), "s3:DeleteBucketPolicy")
    ])
    error_message = "The scope never writes bucket policies; the role must not be able to."
  }

  assert {
    condition = length(setsubtract(
      ["CloudFrontDistribution", "CloudFrontManagedPolicyLookup", "ACMCertificates", "Route53DNS", "WAFv2WebACLLookup", "LambdaEdgeAssociation"],
      [for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement : s.Sid]
    )) == 0
    error_message = "The non-S3 statements must stay in the policy."
  }
}

run "without_state_bucket_keeps_s3_on_every_bucket" {
  command = plan

  # assets_bucket_arn alone only feeds the OAC output; access stays as before.
  variables {
    assets_bucket_arn = "arn:aws:s3:::assets-bucket"
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement :
      s.Resource if startswith(s.Sid, "S3")
    ] == [["*"]]
    error_message = "Without state_bucket_arn, S3 access stays in one statement on every bucket."
  }

  assert {
    condition     = output.cloudfront_oac_bucket_policy_json != ""
    error_message = "assets_bucket_arn still emits the OAC statement."
  }
}

run "state_bucket_scopes_s3_access" {
  command = plan

  variables {
    assets_bucket_arn = "arn:aws:s3:::assets-bucket"
    state_bucket_arn  = "arn:aws:s3:::state-bucket"
  }

  assert {
    condition = { for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement : s.Sid => {
      actions = toset(flatten([s.Action]))
      resources = toset(flatten([s.Resource])) } if startswith(s.Sid, "S3")
      } == {
      S3AssetsBucketRead = {
        actions   = toset(["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketPolicy"])
        resources = toset(["arn:aws:s3:::assets-bucket"])
      }
      S3StateBucketList = {
        actions   = toset(["s3:ListBucket"])
        resources = toset(["arn:aws:s3:::state-bucket"])
      }
      S3StateObjects = {
        actions   = toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"])
        resources = toset(["arn:aws:s3:::state-bucket/nullplatform/scopes/static-files/*"])
      }
    }
    error_message = "With state_bucket_arn, S3 access is limited to the assets bucket reads and the scope's state prefix."
  }
}

run "state_bucket_without_assets_bucket" {
  command = plan

  variables {
    state_bucket_arn = "arn:aws:s3:::state-bucket"
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement :
      s.Resource if s.Sid == "S3StateObjects"
    ]) == ["arn:aws:s3:::state-bucket/nullplatform/scopes/static-files/*"]
    error_message = "State objects are scoped even without assets_bucket_arn."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement :
      s.Resource if s.Sid == "S3AssetsBucketRead"
    ]) == ["*"]
    error_message = "Without assets_bucket_arn, bucket reads stay on every bucket."
  }
}

run "assets_bucket_path_is_reduced_to_the_bucket" {
  command = plan

  variables {
    assets_bucket_arn = "arn:aws:s3:::assets-bucket/app"
    state_bucket_arn  = "arn:aws:s3:::state-bucket"
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_policy.nullplatform_static_files[0].policy).Statement :
      s.Resource if s.Sid == "S3AssetsBucketRead"
    ]) == ["arn:aws:s3:::assets-bucket"]
    error_message = "Bucket reads need the bucket ARN, not an object path."
  }
}

run "iam_create_role_false_creates_nothing" {
  command = plan

  variables {
    iam_create_role  = false
    state_bucket_arn = "arn:aws:s3:::state-bucket"
  }

  assert {
    condition     = length(aws_iam_policy.nullplatform_static_files) == 0
    error_message = "No policy when iam_create_role is false."
  }
}

run "state_bucket_arn_rejects_a_path" {
  command = plan

  variables {
    state_bucket_arn = "arn:aws:s3:::state-bucket/prefix"
  }

  expect_failures = [var.state_bucket_arn]
}

run "state_bucket_arn_rejects_a_bucket_name" {
  command = plan

  variables {
    state_bucket_arn = "state-bucket"
  }

  expect_failures = [var.state_bucket_arn]
}
