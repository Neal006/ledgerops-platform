terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap is the one stack with local state: it creates the bucket everyone else uses.
  # After the first apply, migrate it with `terraform init -migrate-state` and backend.hcl.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "ledgerops"
      stack      = "bootstrap"
      managed_by = "terraform"
    }
  }
}
