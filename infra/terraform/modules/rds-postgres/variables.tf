variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Isolated database subnets."
  type        = list(string)
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect on 5432, keyed by a static name (e.g. ledger_api) so plans stay deterministic."
  type        = map(string)
}

variable "engine_version" {
  type    = string
  default = "17.6"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "allocated_storage_gb" {
  type    = number
  default = 50
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling; prevents a full disk from becoming an outage."
  type        = number
  default     = 500
}

variable "multi_az" {
  type    = bool
  default = true
}

variable "backup_retention_days" {
  description = "Automated backup + WAL retention; this is the point-in-time-recovery window."
  type        = number
  default     = 35
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "enable_proxy" {
  description = "Front the database with RDS Proxy for connection pooling across ECS tasks."
  type        = bool
  default     = true
}

variable "backup_replica_enabled" {
  description = "Replicate automated backups to var.backup_replica provider's region. Must stay within the data residency boundary."
  type        = bool
  default     = false
}

variable "database_name" {
  type    = string
  default = "ledger"
}
