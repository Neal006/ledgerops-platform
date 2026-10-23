variable "region" {
  description = "Home region for the state bucket and IAM (IAM is global)."
  type        = string
  default     = "ap-south-1"
}

variable "github_repository" {
  description = "owner/name of the repository allowed to assume CI roles."
  type        = string
  default     = "Neal006/ledgerops-platform"
}

variable "deploy_environments" {
  description = "GitHub environments allowed to apply Terraform and deploy. Each should have required reviewers."
  type        = list(string)
  default     = ["staging", "production-in", "production-ae"]
}
