output "api_url" {
  value = "https://${var.domain_name}"
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ledger_api_service" {
  value = module.ledger_api.service_name
}

output "ledger_api_task_family" {
  value = module.ledger_api.task_definition_family
}

output "recon_task_family" {
  value = module.recon_worker.task_definition_family
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ledger_api_security_group_id" {
  value = module.ledger_api.security_group_id
}

output "db_instance_identifier" {
  value = module.database.instance_identifier
}

output "statements_bucket" {
  value = aws_s3_bucket.statements.bucket
}
