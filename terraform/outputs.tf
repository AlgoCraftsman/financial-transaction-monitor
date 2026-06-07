# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_transactions_table_name" {
  description = "Name of the transactions DynamoDB table"
  value       = aws_dynamodb_table.transactions.name
}

output "dynamodb_transactions_table_arn" {
  description = "ARN of the transactions DynamoDB table"
  value       = aws_dynamodb_table.transactions.arn
}

output "dynamodb_fraud_alerts_table_name" {
  description = "Name of the fraud alerts DynamoDB table"
  value       = aws_dynamodb_table.fraud_alerts.name
}

output "dynamodb_fraud_alerts_table_arn" {
  description = "ARN of the fraud alerts DynamoDB table"
  value       = aws_dynamodb_table.fraud_alerts.arn
}

# ============================================================================
# SQS Outputs
# ============================================================================

output "sqs_transaction_queue_url" {
  description = "URL of the transaction processing queue"
  value       = aws_sqs_queue.transaction_queue.url
}

output "sqs_transaction_queue_arn" {
  description = "ARN of the transaction processing queue"
  value       = aws_sqs_queue.transaction_queue.arn
}

output "sqs_transaction_dlq_url" {
  description = "URL of the transaction dead-letter queue"
  value       = aws_sqs_queue.transaction_dlq.url
}

output "sqs_transaction_dlq_arn" {
  description = "ARN of the transaction dead-letter queue"
  value       = aws_sqs_queue.transaction_dlq.arn
}

output "sqs_fraud_alert_queue_url" {
  description = "URL of the fraud alert queue"
  value       = aws_sqs_queue.fraud_alert_queue.url
}

output "sqs_fraud_alert_queue_arn" {
  description = "ARN of the fraud alert queue"
  value       = aws_sqs_queue.fraud_alert_queue.arn
}

output "sqs_fraud_alert_dlq_url" {
  description = "URL of the fraud alert dead-letter queue"
  value       = aws_sqs_queue.fraud_alert_dlq.url
}

output "sqs_fraud_alert_dlq_arn" {
  description = "ARN of the fraud alert dead-letter queue"
  value       = aws_sqs_queue.fraud_alert_dlq.arn
}

# ============================================================================
# S3 Outputs
# ============================================================================

output "s3_transaction_logs_bucket_name" {
  description = "Name of the S3 bucket for transaction logs"
  value       = aws_s3_bucket.transaction_logs.id
}

output "s3_transaction_logs_bucket_arn" {
  description = "ARN of the S3 bucket for transaction logs"
  value       = aws_s3_bucket.transaction_logs.arn
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "iam_transaction_processor_role_arn" {
  description = "ARN of the transaction processor Lambda IAM role"
  value       = aws_iam_role.transaction_processor_lambda.arn
}

output "iam_transaction_processor_role_name" {
  description = "Name of the transaction processor Lambda IAM role"
  value       = aws_iam_role.transaction_processor_lambda.name
}

output "iam_fraud_detector_role_arn" {
  description = "ARN of the fraud detector Lambda IAM role"
  value       = aws_iam_role.fraud_detector_lambda.arn
}

output "iam_fraud_detector_role_name" {
  description = "Name of the fraud detector Lambda IAM role"
  value       = aws_iam_role.fraud_detector_lambda.name
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

output "cloudwatch_transaction_processor_log_group" {
  description = "CloudWatch log group for transaction processor Lambda"
  value       = aws_cloudwatch_log_group.transaction_processor.name
}

output "cloudwatch_fraud_detector_log_group" {
  description = "CloudWatch log group for fraud detector Lambda"
  value       = aws_cloudwatch_log_group.fraud_detector.name
}

# ============================================================================
# Account & Region Information
# ============================================================================

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = var.aws_region
}

# ============================================================================
# Environment Information
# ============================================================================

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

# ============================================================================
# Configuration Summary
# ============================================================================

output "deployment_summary" {
  description = "Summary of key deployment configurations"
  value = {
    environment            = var.environment
    region                 = var.aws_region
    lambda_runtime         = var.lambda_runtime
    fraud_risk_threshold   = var.fraud_risk_threshold
    xray_tracing_enabled   = var.enable_xray_tracing
    api_key_required       = var.enable_api_key_required
    point_in_time_recovery = var.enable_point_in_time_recovery
  }
}

# ============================================================================
# Next Steps Output
# ============================================================================

output "next_steps" {
  description = "Helpful next steps after Terraform apply"
  value       = <<-EOT
      Infrastructure deployed successfully!
    
    Next steps:
    1. Deploy Lambda functions:
       - Transaction Processor: /aws/lambda/${var.project_name}-transaction-processor-${var.environment}
       - Fraud Detector: /aws/lambda/${var.project_name}-fraud-detector-${var.environment}
    
    2. Test the transaction queue:
       aws sqs send-message --queue-url ${aws_sqs_queue.transaction_queue.url} --message-body '{"test": "message"}'
    
    3. Monitor CloudWatch Logs:
       - ${aws_cloudwatch_log_group.transaction_processor.name}
       - ${aws_cloudwatch_log_group.fraud_detector.name}
    
    4. View DynamoDB tables:
       - Transactions: ${aws_dynamodb_table.transactions.name}
       - Fraud Alerts: ${aws_dynamodb_table.fraud_alerts.name}
    
    5. Check S3 logs bucket:
       aws s3 ls s3://${aws_s3_bucket.transaction_logs.id}/
    
    6. Configure remote state (recommended for production):
       - Uncomment backend block in main.tf
       - Create S3 bucket and DynamoDB table for state locking
    
    7. Enable additional features for production:
       - Set enable_point_in_time_recovery = true
       - Set enable_waf = true
       - Configure alert_email_addresses
       - Set up Slack notifications
  EOT
}
