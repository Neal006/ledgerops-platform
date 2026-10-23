variable "name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "image" {
  type = string
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression, e.g. cron(30 6 * * ? *)."
  type        = string
}

variable "schedule_timezone" {
  type    = string
  default = "UTC"
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "secrets" {
  type    = map(string)
  default = {}
}

variable "secret_arns" {
  type    = list(string)
  default = []
}

variable "kms_key_arns" {
  type    = list(string)
  default = []
}

variable "task_role_policy_json" {
  type    = string
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 365
}
