variable "name" {
  description = "Name prefix, e.g. ledgerops-prod-in."
  type        = string
}

variable "cidr_block" {
  type = string
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheap, lower envs) instead of one per AZ (HA, production)."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  type    = number
  default = 90
}
