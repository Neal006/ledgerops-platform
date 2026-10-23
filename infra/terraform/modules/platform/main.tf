data "aws_caller_identity" "current" {}

module "network" {
  source             = "../network"
  name               = var.name
  cidr_block         = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}

# --- Edge: ALB, TLS, DNS -----------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public HTTPS ingress"
  vpc_id      = module.network.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = module.network.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
}

resource "aws_lb" "this" {
  name                       = substr(replace(var.name, "ledgerops-", "lo-"), 0, 32)
  load_balancer_type         = "application"
  subnets                    = module.network.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.environment == "production"
  idle_timeout               = 60
}

resource "aws_acm_certificate" "api" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_validation" {
  for_each = {
    for o in aws_acm_certificate.api.domain_validation_options : o.domain_name => o
  }
  zone_id = var.hosted_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_route53_record.api_validation : r.fqdn]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.api.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not_found\"}"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Internal endpoints are never routed publicly, whatever host header is sent.
resource "aws_lb_listener_rule" "block_internal" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not_found\"}"
      status_code  = "404"
    }
  }
  condition {
    path_pattern {
      values = ["/metrics", "/metrics/*"]
    }
  }
}

resource "aws_route53_record" "api" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# --- Broker statements (input to reconciliation) -----------------------------------------------

resource "aws_s3_bucket" "statements" {
  bucket = "${var.name}-broker-statements-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "statements" {
  bucket = aws_s3_bucket.statements.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "statements" {
  bucket = aws_s3_bucket.statements.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "statements" {
  bucket                  = aws_s3_bucket.statements.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Database ----------------------------------------------------------------------------------

module "database" {
  source = "../rds-postgres"
  providers = {
    aws                = aws
    aws.backup_replica = aws.backup_replica
  }

  name                   = var.name
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.database_subnet_ids
  instance_class         = var.db_instance_class
  multi_az               = var.db_multi_az
  deletion_protection    = var.db_deletion_protection
  backup_retention_days  = var.db_backup_retention_days
  backup_replica_enabled = var.db_backup_replica_enabled
  client_security_group_ids = {
    ledger_api   = module.ledger_api.security_group_id
    recon_worker = module.recon_worker.security_group_id
  }
}

locals {
  db_secret = module.database.master_secret_arn
  db_credentials = {
    PGUSER     = "${local.db_secret}:username::"
    PGPASSWORD = "${local.db_secret}:password::"
  }
}

# --- Workloads ---------------------------------------------------------------------------------

module "ledger_api" {
  source = "../ecs-service"

  name                   = "${var.name}-ledger-api"
  cluster_arn            = aws_ecs_cluster.this.arn
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  image                  = var.ledger_api_image
  alb_listener_arn       = aws_lb_listener.https.arn
  alb_security_group_id  = aws_security_group.alb.id
  listener_rule_priority = 10
  host_header            = var.domain_name
  desired_count          = var.api_desired_count
  min_count              = var.api_desired_count
  max_count              = var.api_max_count
  log_retention_days     = var.log_retention_days
  rollback_alarm_names   = module.observability.deployment_rollback_alarm_names

  environment = {
    APP_ENV        = var.environment
    LEDGER_BOOK    = var.book
    PGHOST         = module.database.app_endpoint
    PGDATABASE     = module.database.database_name
    PGSSLMODE      = "verify-full"
    DB_DIRECT_HOST = module.database.address # migrations bypass the proxy (session advisory locks)
    DB_POOL_MAX    = "10"
  }
  secrets      = local.db_credentials
  secret_arns  = [local.db_secret]
  kms_key_arns = [module.database.kms_key_arn]
}

data "aws_iam_policy_document" "recon_task" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.statements.arn}/statements/*"]
  }
}

module "recon_worker" {
  source = "../scheduled-task"

  name                  = "${var.name}-recon-worker"
  cluster_arn           = aws_ecs_cluster.this.arn
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.private_subnet_ids
  image                 = var.recon_worker_image
  schedule_expression   = var.recon_schedule
  schedule_timezone     = var.recon_timezone
  task_role_policy_json = data.aws_iam_policy_document.recon_task.json

  environment = {
    APP_ENV       = var.environment
    LEDGER_BOOK   = var.book
    PGHOST        = module.database.address
    PGDATABASE    = module.database.database_name
    PGSSLMODE     = "verify-full"
    STATEMENT_URI = "s3://${aws_s3_bucket.statements.bucket}/statements/latest.csv"
  }
  secrets      = local.db_credentials
  secret_arns  = [local.db_secret]
  kms_key_arns = [module.database.kms_key_arn]
}

module "observability" {
  source = "../observability"

  name                    = var.name
  environment             = var.environment
  book                    = var.book
  alb_arn_suffix          = aws_lb.this.arn_suffix
  target_group_arn_suffix = module.ledger_api.target_group_arn_suffix
  db_instance_identifier  = module.database.instance_identifier
  alert_email             = var.alert_email
}
