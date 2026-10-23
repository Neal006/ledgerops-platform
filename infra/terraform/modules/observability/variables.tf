variable "name" {
  type = string
}

variable "environment" {
  description = "Value of the Environment dimension emitted by the recon job."
  type        = string
}

variable "book" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "db_instance_identifier" {
  type = string
}

variable "db_max_connections" {
  description = "Approximate max_connections for the instance class, for the connection alarm."
  type        = number
  default     = 400
}

variable "alert_email" {
  description = "Optional email subscriber; production should use a chat/paging HTTPS endpoint."
  type        = string
  default     = null
}

variable "alert_https_endpoint" {
  description = "Optional HTTPS endpoint (e.g. PagerDuty/Opsgenie/Slack relay) for the page topic."
  type        = string
  default     = null
}
