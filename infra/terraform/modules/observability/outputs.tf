output "page_topic_arn" {
  value = aws_sns_topic.this["page"].arn
}

output "ticket_topic_arn" {
  value = aws_sns_topic.this["ticket"].arn
}

output "deployment_rollback_alarm_names" {
  description = "Alarms ECS watches during a deployment to trigger automatic rollback."
  value       = [aws_cloudwatch_metric_alarm.api_5xx_ratio.alarm_name]
}
