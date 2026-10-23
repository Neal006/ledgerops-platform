# Symptom-based CloudWatch alarms. Two topics:
#   page   - customer-visible impact or money at risk; wakes someone up
#   ticket - degradation that can wait for business hours

resource "aws_kms_key" "sns" {
  description         = "${var.name} alert topics"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.sns_kms.json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "sns_kms" {
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchPublish"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic" "this" {
  for_each          = toset(["page", "ticket"])
  name              = "${var.name}-${each.key}"
  kms_master_key_id = aws_kms_key.sns.id
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = var.alert_email == null ? toset([]) : toset(["page", "ticket"])
  topic_arn = aws_sns_topic.this[each.key].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "pager" {
  count                  = var.alert_https_endpoint == null ? 0 : 1
  topic_arn              = aws_sns_topic.this["page"].arn
  protocol               = "https"
  endpoint               = var.alert_https_endpoint
  endpoint_auto_confirms = true
}

locals {
  page   = [aws_sns_topic.this["page"].arn]
  ticket = [aws_sns_topic.this["ticket"].arn]
}

# --- Ledger API (ALB) --------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "api_5xx_ratio" {
  alarm_name          = "${var.name}-api-5xx-ratio"
  alarm_description   = "More than 1% of ledger API requests are failing. Also drives ECS deployment rollback. Runbook: docs/runbooks/high-error-rate.md"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.page
  ok_actions          = local.page

  metric_query {
    id          = "ratio"
    expression  = "IF(requests > 20, 100 * (errors_target + errors_elb) / requests, 0)"
    label       = "5xx %"
    return_data = true
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      stat        = "Sum"
      period      = 60
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
    }
  }
  metric_query {
    id = "errors_target"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      stat        = "Sum"
      period      = 60
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
    }
  }
  metric_query {
    id = "errors_elb"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      stat        = "Sum"
      period      = 60
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_latency_p99" {
  alarm_name          = "${var.name}-api-latency-p99"
  alarm_description   = "Ledger API p99 latency above 1s. Runbook: docs/runbooks/high-latency.md"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p99"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.page
  ok_actions          = local.page
}

resource "aws_cloudwatch_metric_alarm" "api_no_healthy_hosts" {
  alarm_name          = "${var.name}-api-no-healthy-hosts"
  alarm_description   = "No healthy ledger API targets behind the ALB."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.page
  ok_actions          = local.page
}

# --- Database ----------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.name}-db-connections-high"
  alarm_description   = "DB connections above 80% of max. Runbook: docs/runbooks/db-connection-exhaustion.md"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  period              = 60
  evaluation_periods  = 5
  threshold           = floor(var.db_max_connections * 0.8)
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.ticket
}

resource "aws_cloudwatch_metric_alarm" "db_free_storage" {
  alarm_name          = "${var.name}-db-free-storage-low"
  alarm_description   = "Less than 10 GiB free on the ledger database."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  period              = 300
  evaluation_periods  = 2
  threshold           = 10 * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  alarm_actions       = local.page
}

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name}-db-cpu-high"
  alarm_description   = "Ledger database CPU above 80% for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.ticket
}

# --- Reconciliation (custom metrics emitted by the job via EMF) ---------------------------------

resource "aws_cloudwatch_metric_alarm" "recon_breaks" {
  alarm_name          = "${var.name}-recon-breaks"
  alarm_description   = "Ledger does not reconcile with the broker. Money may be at risk. Runbook: docs/runbooks/recon-breaks.md"
  namespace           = "LedgerOps/Recon"
  metric_name         = "ReconBreaks"
  statistic           = "Maximum"
  dimensions          = { Environment = var.environment, Book = var.book }
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.page
  ok_actions          = local.page
}

resource "aws_cloudwatch_metric_alarm" "recon_stale" {
  alarm_name          = "${var.name}-recon-stale"
  alarm_description   = "Dead man's switch: no successful reconciliation in 26h. Runbook: docs/runbooks/recon-breaks.md"
  namespace           = "LedgerOps/Recon"
  metric_name         = "ReconSuccess"
  statistic           = "Sum"
  dimensions          = { Environment = var.environment, Book = var.book }
  period              = 3600
  evaluation_periods  = 26
  datapoints_to_alarm = 26
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  # Missing data IS the failure signal for a job that didn't run.
  treat_missing_data = "breaching"
  alarm_actions      = local.page
  ok_actions         = local.page
}
