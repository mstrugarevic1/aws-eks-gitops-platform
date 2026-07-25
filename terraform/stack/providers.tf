provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = var.deployment_role_arn
    session_name = "${var.project}-${var.environment}-terraform"
  }

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }
}

data "aws_caller_identity" "current" {}

check "target_aws_account" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
    error_message = "Terraform authenticated against an unexpected AWS account."
  }
}
