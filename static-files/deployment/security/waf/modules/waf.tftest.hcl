# =============================================================================
# Unit tests for security/waf module
#
# Run: tofu test
# =============================================================================

mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test-acl/abcdef12-3456-7890-abcd-ef1234567890"
      id  = "abcdef12-3456-7890-abcd-ef1234567890"
    }
  }
}

variables {
  security_web_acl_name = "test-acl"
}

run "resolves_web_acl_arn_from_name" {
  command = plan

  assert {
    condition     = local.security_web_acl_arn == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test-acl/abcdef12-3456-7890-abcd-ef1234567890"
    error_message = "security_web_acl_arn should match the ARN returned by the data source"
  }

  assert {
    condition     = output.security_web_acl_arn == local.security_web_acl_arn
    error_message = "output should mirror the local"
  }
}

run "data_source_is_called_with_cloudfront_scope" {
  command = plan

  assert {
    condition     = data.aws_wafv2_web_acl.cloudfront.scope == "CLOUDFRONT"
    error_message = "data source must always query scope=CLOUDFRONT"
  }

  assert {
    condition     = data.aws_wafv2_web_acl.cloudfront.name == "test-acl"
    error_message = "data source name should match the input variable"
  }
}
