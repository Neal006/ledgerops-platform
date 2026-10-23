# Account-wide resources shared by every environment: container registries.
# Images are built once, pushed to ap-south-1, and replicated to me-central-1 so the UAE stack
# pulls in-region. The exact same digest is promoted staging -> prod-in -> prod-ae.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key          = "global/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = { project = "ledgerops", stack = "global", managed_by = "terraform" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  repositories        = ["ledgerops/ledger-api", "ledgerops/recon-worker"]
  replication_regions = ["me-central-1"]
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(local.repositories)
  name                 = each.key
  image_tag_mutability = "IMMUTABLE" # a tag (git SHA) always means the same bytes

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Drop untagged layers after 7 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last 100 images (rollback window)"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 100 }
        action       = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_replication_configuration" "this" {
  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = local.replication_regions
        content {
          region      = destination.value
          registry_id = data.aws_caller_identity.current.account_id
        }
      }
      repository_filter {
        filter      = "ledgerops/"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
