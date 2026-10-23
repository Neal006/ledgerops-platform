variable "name" {
  description = "Service name, e.g. ledgerops-prod-in-ledger-api. Roles are prefixed ledgerops- so CI can pass them."
  type        = string
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
  description = "Initial image. CI owns subsequent revisions; Terraform ignores task definition drift."
  type        = string
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "environment" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Env var name -> Secrets Manager valueFrom (ARN, optionally with :json-key::)."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secret ARNs the execution role may read (without JSON key suffixes)."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS keys used to encrypt the secrets above."
  type        = list(string)
  default     = []
}

variable "task_role_policy_json" {
  description = "Least-privilege policy for the application itself. Null for no AWS access."
  type        = string
  default     = null
}

variable "alb_listener_arn" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "listener_rule_priority" {
  type = number
}

variable "host_header" {
  type = string
}

variable "health_check_path" {
  type    = string
  default = "/readyz"
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_count" {
  type    = number
  default = 2
}

variable "max_count" {
  type    = number
  default = 10
}

variable "rollback_alarm_names" {
  description = "CloudWatch alarms that, if they fire during a deployment, make ECS roll it back."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 90
}
