# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_transactions_table_name" {
  description = "Name of the transactions DynamoDB table"
  value       = aws_dynamodb_table.transactions.name
}

output "dynamodb_fraud_alerts_table_name" {
  description = "Name of the fraud alerts DynamoDB table"
  value       = aws_dynamodb_table.fraud_alerts.name
}

# ============================================================================
# SQS Outputs
# ============================================================================

output "sqs_transaction_queue_url" {
  description = "URL of the transaction processing queue"
  value       = aws_sqs_queue.transaction_queue.url
}

output "sqs_transaction_dlq_url" {
  description = "URL of the transaction dead-letter queue"
  value       = aws_sqs_queue.transaction_dlq.url
}

output "sqs_fraud_alert_queue_url" {
  description = "URL of the fraud alert queue"
  value       = aws_sqs_queue.fraud_alert_queue.url
}

output "sqs_fraud_alert_dlq_url" {
  description = "URL of the fraud alert dead-letter queue"
  value       = aws_sqs_queue.fraud_alert_dlq.url
}

# ============================================================================
# S3 Outputs
# ============================================================================

output "s3_transaction_logs_bucket_name" {
  description = "Name of the S3 bucket for transaction and alert audit logs"
  value       = aws_s3_bucket.transaction_logs.id
}

# ============================================================================
# Lambda Outputs
# ============================================================================

output "transaction_processor_function_name" {
  description = "Name of the transaction processor Lambda function"
  value       = aws_lambda_function.transaction_processor.function_name
}

output "fraud_detector_function_name" {
  description = "Name of the fraud detector Lambda function"
  value       = aws_lambda_function.fraud_detector.function_name
}

output "api_handler_function_name" {
  description = "Name of the API handler Lambda function"
  value       = aws_lambda_function.api_handler.function_name
}

# ============================================================================
# API Outputs
# ============================================================================

output "api_endpoint" {
  description = "Base URL for the transaction monitoring HTTP API"
  value       = aws_apigatewayv2_api.monitoring_api.api_endpoint
}

output "api_routes" {
  description = "Implemented API routes"
  value = [
    "GET /health",
    "GET /transactions/{transaction_id}?timestamp={timestamp}",
    "GET /transactions/user/{user_id}",
    "GET /alerts?status=open",
    "GET /alerts/{alert_id}",
    "PATCH /alerts/{alert_id}/status"
  ]
}

# ============================================================================
# Notification Outputs
# ============================================================================

output "fraud_alert_topic_arn" {
  description = "SNS topic ARN for high-risk fraud alert notifications"
  value       = aws_sns_topic.fraud_alerts.arn
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard for pipeline health"
  value       = aws_cloudwatch_dashboard.pipeline.dashboard_name
}

# ============================================================================
# CloudWatch Alarm Outputs
# ============================================================================

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms created for runtime health"
  value = [
    aws_cloudwatch_metric_alarm.transaction_processor_errors.alarm_name,
    aws_cloudwatch_metric_alarm.fraud_detector_errors.alarm_name,
    aws_cloudwatch_metric_alarm.api_handler_errors.alarm_name,
    aws_cloudwatch_metric_alarm.transaction_processor_duration.alarm_name,
    aws_cloudwatch_metric_alarm.fraud_detector_duration.alarm_name,
    aws_cloudwatch_metric_alarm.api_handler_duration.alarm_name,
    aws_cloudwatch_metric_alarm.transaction_dlq_messages.alarm_name,
    aws_cloudwatch_metric_alarm.fraud_alert_dlq_messages.alarm_name
  ]
}

# ============================================================================
# Environment Outputs
# ============================================================================

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = var.aws_region
}

output "deployment_summary" {
  description = "Summary of key deployment settings"
  value = {
    environment                 = var.environment
    region                      = var.aws_region
    lambda_runtime              = var.lambda_runtime
    fraud_risk_threshold        = var.fraud_risk_threshold
    velocity_check_window_mins  = var.velocity_check_window_minutes
    xray_tracing_enabled        = var.enable_xray_tracing
    point_in_time_recovery_used = var.enable_point_in_time_recovery || var.environment == "production"
    cloudwatch_alarms           = 8
    api_endpoint                = aws_apigatewayv2_api.monitoring_api.api_endpoint
  }
}

output "next_steps" {
  description = "Useful commands after Terraform apply"
  value       = <<-EOT
    Infrastructure deployed successfully.

    Send a sample transaction:
      python ../data-generator/generate_transactions.py --count 1 --queue-url ${aws_sqs_queue.transaction_queue.url}

    Inspect Lambda logs:
      aws logs tail ${aws_cloudwatch_log_group.transaction_processor.name} --follow --region ${var.aws_region}
      aws logs tail ${aws_cloudwatch_log_group.fraud_detector.name} --follow --region ${var.aws_region}

    Review persisted data:
      aws dynamodb scan --table-name ${aws_dynamodb_table.transactions.name} --limit 5 --region ${var.aws_region}
      aws dynamodb scan --table-name ${aws_dynamodb_table.fraud_alerts.name} --limit 5 --region ${var.aws_region}

    Query the API:
      curl ${aws_apigatewayv2_api.monitoring_api.api_endpoint}/health
  EOT
}
