terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_provider.region

  default_tags {
    tags = var.provider_resource_tags_json
  }
}

# Global provider for resources that must live in us-east-1 (e.g., ACM certificates for CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.provider_resource_tags_json
  }
}