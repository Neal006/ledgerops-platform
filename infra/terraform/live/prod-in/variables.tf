variable "aws_account_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "book" {
  type = string
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
  type = string
}

variable "hosted_zone_id" {
  type = string
}

variable "initial_image_tag" {
  description = "Tag used only on first creation; CI owns image versions afterwards."
  type        = string
  default     = "bootstrap"
}

variable "api_desired_count" {
  type    = number
  default = 2
}

variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

variable "db_backup_replica_enabled" {
  type    = bool
  default = false
}

variable "recon_timezone" {
  type = string
}

variable "alert_email" {
  type    = string
  default = null
}
