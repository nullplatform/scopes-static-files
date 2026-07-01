terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Static-files requirements only read data.aws_caller_identity.
      version = ">= 5.0"
    }
  }
}
