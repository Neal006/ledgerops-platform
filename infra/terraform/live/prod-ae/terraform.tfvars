# UAE book. me-central-1 is the only in-country AWS region, so backups are not replicated
# cross-region (Bahrain would leave the jurisdiction); Multi-AZ + PITR + snapshots cover DR.
aws_account_id            = "111111111111" # replace with your account ID
environment               = "production"
book                      = "AE"
vpc_cidr                  = "10.30.0.0/16"
az_count                  = 3
domain_name               = "ledger.ae.example.com"
hosted_zone_id            = "Z0000000000000PRODAE"
api_desired_count         = 2
db_instance_class         = "db.r7g.large"
db_multi_az               = true
db_backup_replica_enabled = false
recon_timezone            = "Asia/Dubai"
