# Look up the WAFv2 WebACL by name.
# WebACLs with scope=CLOUDFRONT live only in us-east-1, hence the aws.us_east_1 alias.
data "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = var.security_web_acl_name
  scope    = "CLOUDFRONT"
}
