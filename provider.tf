locals {
  allowed_account_ids = [var.account]
  profile_name        = var.profile_name
  region              = var.aws_region
}


provider "aws" {
  allowed_account_ids = local.allowed_account_ids
  region              = local.region
  profile             = local.profile_name


  default_tags {
    tags = {
      managed_by = "terraform"
    }
  }
}
