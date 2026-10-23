variable "environment" {
  description = "staging or production."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "book" {
  description = "Regulated book served by this stack: IN (IFSCA / GIFT City) or AE (UAE)."
  type        = string
  validation {
    condition     = contains(["IN", "AE"], var.book)
    error_message = "book must be IN or AE."
  }
}

variable "name" {
  description = "Stack name prefix; must start with ledgerops- (CI PassRole is scoped to it)."
  type        = string
  validation {
    condition     = startswith(var.name, "ledgerops-")
    error_message = "name must start with ledgerops-."
  }
}

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  type    = bool
  default = false
}

variable "domain_name" {
  description = "Public hostname for the ledger API, e.g. ledger.in.example.com."
  type        = string
}

variable "hosted_zone_id" {
  type = string
}

variable "ledger_api_image" {
  type = string
}

variable "recon_worker_image" {
  type = string
}

variable "api_desired_count" {
  type    = number
  default = 2
}

variable "api_max_count" {
  type    = number
  default = 10
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 35
}

variable "db_backup_replica_enabled" {
  type    = bool
  default = false
}

variable "recon_schedule" {
  description = "When the daily reconciliation runs, after the broker's EOD statement lands."
  type        = string
  default     = "cron(30 7 * * ? *)"
}

variable "recon_timezone" {
  type    = string
  default = "Asia/Kolkata"
}

variable "alert_email" {
  type    = string
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 90
}
