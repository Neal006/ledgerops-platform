# India book: IFSCA / GIFT City entity. Data and backups stay in India (Mumbai + Hyderabad).
aws_account_id            = "111111111111" # replace with your account ID
environment               = "production"
book                      = "IN"
vpc_cidr                  = "10.20.0.0/16"
az_count                  = 3
domain_name               = "ledger.in.example.com"
hosted_zone_id            = "Z0000000000000PRODIN"
api_desired_count         = 3
db_instance_class         = "db.r7g.large"
db_multi_az               = true
db_backup_replica_enabled = true # ap-south-2 (Hyderabad), still in-country
recon_timezone            = "Asia/Kolkata"
