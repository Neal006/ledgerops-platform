resource "aws_kms_key" "this" {
  description             = "${var.name} RDS storage, snapshots and master secret"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres access from approved client security groups only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = var.client_security_group_ids
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from ${each.key}"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg17"
  family = "postgres17"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  # Surface slow queries and lock contention in logs; both are early warnings of migration trouble.
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
  # A forgotten open transaction holds locks and blocks vacuum; kill it after 60s.
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "60000"
  }
  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.database_name
  username       = "ledger_admin"

  # RDS generates and stores the master password in Secrets Manager and rotates it.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.key_id

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_days
  backup_window             = "20:30-21:30" # ~02:00 IST / 00:30 GST, outside both markets' hours
  maintenance_window        = "sun:22:00-sun:23:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  auto_minor_version_upgrade            = true
  allow_major_version_upgrade           = false
  iam_database_authentication_enabled   = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.this.arn
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
}

# Off-region copies of automated backups (and their WAL) for regional disaster recovery.
# For the India book this targets ap-south-2 (Hyderabad) so data never leaves India.
resource "aws_db_instance_automated_backups_replication" "this" {
  count    = var.backup_replica_enabled ? 1 : 0
  provider = aws.backup_replica

  source_db_instance_arn = aws_db_instance.this.arn
  retention_period       = var.backup_retention_days
  kms_key_id             = aws_kms_key.replica[0].arn
}

resource "aws_kms_key" "replica" {
  count    = var.backup_replica_enabled ? 1 : 0
  provider = aws.backup_replica

  description         = "${var.name} replicated RDS backups"
  enable_key_rotation = true
}

# --- RDS Proxy: pools connections so scaling ECS tasks out can't exhaust max_connections. -----

resource "aws_security_group" "proxy" {
  count       = var.enable_proxy ? 1 : 0
  name        = "${var.name}-db-proxy"
  description = "RDS Proxy for ${var.name}"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "proxy_clients" {
  for_each                     = var.enable_proxy ? var.client_security_group_ids : {}
  security_group_id            = aws_security_group.proxy[0].id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_db" {
  count                        = var.enable_proxy ? 1 : 0
  security_group_id            = aws_security_group.proxy[0].id
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_proxy" {
  count                        = var.enable_proxy ? 1 : 0
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.proxy[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

data "aws_iam_policy_document" "proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  count              = var.enable_proxy ? 1 : 0
  name               = "${var.name}-db-proxy"
  assume_role_policy = data.aws_iam_policy_document.proxy_assume.json
}

data "aws_iam_policy_document" "proxy" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_role_policy" "proxy" {
  count  = var.enable_proxy ? 1 : 0
  name   = "read-db-secret"
  role   = aws_iam_role.proxy[0].id
  policy = data.aws_iam_policy_document.proxy.json
}

resource "aws_db_proxy" "this" {
  count                  = var.enable_proxy ? 1 : 0
  name                   = var.name
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy[0].arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.proxy[0].id]
  require_tls            = true
  idle_client_timeout    = 1800

  auth {
    auth_scheme               = "SECRETS"
    secret_arn                = aws_db_instance.this.master_user_secret[0].secret_arn
    iam_auth                  = "DISABLED"
    client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  count         = var.enable_proxy ? 1 : 0
  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    max_connections_percent      = 80 # leave headroom for migrations and operators
    max_idle_connections_percent = 30
    connection_borrow_timeout    = 10
  }
}

resource "aws_db_proxy_target" "this" {
  count                  = var.enable_proxy ? 1 : 0
  db_proxy_name          = aws_db_proxy.this[0].name
  target_group_name      = aws_db_proxy_default_target_group.this[0].name
  db_instance_identifier = aws_db_instance.this.identifier
}
