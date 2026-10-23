terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Bucket is supplied at init: terraform init -backend-config=bucket=ledgerops-tfstate-<account>
  backend "s3" {
    key          = "prod-in/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "ap-south-1"
  # Guard against applying this stack with credentials for the wrong account.
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = {
      project     = "ledgerops"
      environment = var.environment
      book        = var.book
      managed_by  = "terraform"
      repo        = "Neal006/ledgerops-platform"
    }
  }
}

# Where automated database backups are replicated. Must stay inside the book's jurisdiction.
provider "aws" {
  alias               = "backup_replica"
  region              = "ap-south-2"
  allowed_account_ids = [var.aws_account_id]
}

locals {
  # ECR lives in ap-south-1 and replicates to me-central-1; always pull from the local region.
  registry = "${var.aws_account_id}.dkr.ecr.ap-south-1.amazonaws.com"
}

module "platform" {
  source = "../../modules/platform"
  providers = {
    aws                = aws
    aws.backup_replica = aws.backup_replica
  }

  name               = "ledgerops-prod-in"
  environment        = var.environment
  book               = var.book
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  domain_name        = var.domain_name
  hosted_zone_id     = var.hosted_zone_id

  ledger_api_image   = "${local.registry}/ledgerops/ledger-api:${var.initial_image_tag}"
  recon_worker_image = "${local.registry}/ledgerops/recon-worker:${var.initial_image_tag}"
  api_desired_count  = var.api_desired_count

  db_instance_class         = var.db_instance_class
  db_multi_az               = var.db_multi_az
  db_deletion_protection    = var.db_deletion_protection
  db_backup_replica_enabled = var.db_backup_replica_enabled
  recon_timezone            = var.recon_timezone
  alert_email               = var.alert_email
}

output "api_url" {
  value = module.platform.api_url
}

output "deploy" {
  description = "Values consumed by scripts/deploy.sh."
  value = {
    region            = "ap-south-1"
    cluster           = module.platform.cluster_name
    service           = module.platform.ledger_api_service
    task_family       = module.platform.ledger_api_task_family
    recon_task_family = module.platform.recon_task_family
    subnets           = module.platform.private_subnet_ids
    security_group    = module.platform.ledger_api_security_group_id
    db_instance       = module.platform.db_instance_identifier
  }
}
