output "instance_identifier" {
  value = aws_db_instance.this.identifier
}

output "address" {
  description = "Direct instance endpoint. Used by migrations (session-level advisory locks pin proxy connections)."
  value       = aws_db_instance.this.address
}

output "app_endpoint" {
  description = "Endpoint the application should use: the proxy when enabled."
  value       = var.enable_proxy ? aws_db_proxy.this[0].endpoint : aws_db_instance.this.address
}

output "database_name" {
  value = aws_db_instance.this.db_name
}

output "master_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}
