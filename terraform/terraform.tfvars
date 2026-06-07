

# General Configuration
project_name = "txn-monitor"
environment  = "dev"
aws_region   = "us-east-2"

# Lambda Configuration
lambda_runtime                = "python3.11"
transaction_processor_memory  = 512
transaction_processor_timeout = 30
fraud_detector_memory         = 1024
fraud_detector_timeout        = 60
lambda_reserved_concurrency   = -1 # -1 means unreserved

# Monitoring & Logging
log_retention_days         = 30
enable_xray_tracing        = true
enable_enhanced_monitoring = false

# Fraud Detection Parameters
fraud_risk_threshold          = 75
velocity_check_window_minutes = 60
max_transactions_per_window   = 10
suspicious_amount_threshold   = 1000.00

# API Gateway Configuration
api_throttle_burst_limit = 100
api_throttle_rate_limit  = 50
enable_api_key_required  = true

# SQS Configuration
sqs_max_receive_count  = 3
sqs_visibility_timeout = 300 # Should be 6x Lambda timeout

# Cost Optimization
enable_dynamodb_autoscaling  = false
s3_lifecycle_glacier_days    = 90
s3_lifecycle_expiration_days = 365

# Alerting & Notifications
alert_email_addresses = [
  # "fraud-team@example.com",
  # "security@example.com"
]
enable_slack_notifications = false
slack_webhook_url          = "" # Store in AWS Secrets Manager for production

# Feature Flags
enable_point_in_time_recovery = false # Set to true for production
enable_vpc_endpoints          = false # Set to true for enhanced security
enable_waf                    = false # Set to true for production

# Additional Tags
additional_tags = {
  CostCenter = "Engineering"
  Owner      = "Platform Team"
  Compliance = "PCI-DSS"
}

# ============================================================================
# Environment-Specific Configurations
# ============================================================================

# Development Environment
# environment                   = "dev"
# log_retention_days            = 7
# enable_point_in_time_recovery = false
# fraud_risk_threshold          = 50  # Lower threshold for testing

# Staging Environment
# environment                   = "staging"
# log_retention_days            = 30
# enable_point_in_time_recovery = true
# fraud_risk_threshold          = 70

# Production Environment
# environment                   = "production"
# log_retention_days            = 90
# enable_point_in_time_recovery = true
# enable_waf                    = true
# enable_vpc_endpoints          = true
# fraud_risk_threshold          = 80
# lambda_reserved_concurrency   = 10  # Reserve capacity
