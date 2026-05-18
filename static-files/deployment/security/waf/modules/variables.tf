variable "security_web_acl_name" {
  description = "Name of an existing WAFv2 WebACL (scope=CLOUDFRONT, us-east-1) to attach to downstream distributions."
  type        = string
}
