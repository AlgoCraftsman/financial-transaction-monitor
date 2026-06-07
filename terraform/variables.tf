

# ============================================================================
# General Configuration
# ============================================================================

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "txn-monitor"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

# ============================================================================
# Lambda Configuration
# ============================================================================

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.11"

  validation {
    condition     = can(regex("^python3\\.(11|12|13)$", var.lambda_runtime))
    error_message = "Lambda runtime must be python3.11 or newer."
  }
}

variable "transaction_processor_memory" {
  description = "Memory allocation for transaction processor Lambda (MB)"
  type        = number
  default     = 512

  validation {
    condition     = var.transaction_processor_memory >= 128 && var.transaction_processor_memory <= 10240
    error_message = "Memory must be between 128 MB and 10240 MB."
  }
}

variable "transaction_processor_timeout" {
  description = "Timeout for transaction processor Lambda (seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.transaction_processor_timeout >= 3 && var.transaction_processor_timeout <= 900
    error_message = "Timeout must be between 3 and 900 seconds."
  }
}

variable "fraud_detector_memory" {
  description = "Memory allocation for fraud detector Lambda (MB)"
  type        = number
  default     = 1024

  validation {
    condition     = var.fraud_detector_memory >= 128 && var.fraud_detector_memory <= 10240
    error_message = "Memory must be between 128 MB and 10240 MB."
  }
}

variable "fraud_detector_timeout" {
  description = "Timeout for fraud detector Lambda (seconds)"
  type        = number
  default     = 60

  validation {
    condition     = var.fraud_detector_timeout >= 3 && var.fraud_detector_timeout <= 900
    error_message = "Timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for Lambda functions (-1 for unreserved)"
  type        = number
  default     = -1

  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "Reserved concurrency must be -1 (unreserved) or a positive number."
  }
}

# ============================================================================
# Monitoring & Logging
# ============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 1 #for testing. 30 for default

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention value."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring"
  type        = bool
  default     = false
}

# ============================================================================
# Fraud Detection Configuration
# ============================================================================

variable "fraud_risk_threshold" {
  description = "Risk score threshold for fraud alerts (0-100)"
  type        = number
  default     = 75

  validation {
    condition     = var.fraud_risk_threshold >= 0 && var.fraud_risk_threshold <= 100
    error_message = "Fraud risk threshold must be between 0 and 100."
  }
}

variable "velocity_check_window_minutes" {
  description = "Time window for velocity checks in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.velocity_check_window_minutes > 0 && var.velocity_check_window_minutes <= 1440
    error_message = "Velocity check window must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "max_transactions_per_window" {
  description = "Maximum allowed transactions per user in the velocity window"
  type        = number
  default     = 10

  validation {
    condition     = var.max_transactions_per_window > 0
    error_message = "Max transactions per window must be greater than 0."
  }
}

variable "suspicious_amount_threshold" {
  description = "Transaction amount that triggers additional scrutiny (USD)"
  type        = number
  default     = 1000.00

  validation {
    condition     = var.suspicious_amount_threshold >= 0
    error_message = "Suspicious amount threshold must be non-negative."
  }
}

# ============================================================================
# API Gateway Configuration
# ============================================================================

variable "api_throttle_burst_limit" {
  description = "API Gateway burst limit for requests"
  type        = number
  default     = 100

  validation {
    condition     = var.api_throttle_burst_limit >= 0
    error_message = "Burst limit must be non-negative."
  }
}

variable "api_throttle_rate_limit" {
  description = "API Gateway rate limit (requests per second)"
  type        = number
  default     = 50

  validation {
    condition     = var.api_throttle_rate_limit >= 0
    error_message = "Rate limit must be non-negative."
  }
}

variable "enable_api_key_required" {
  description = "Require API key for API Gateway endpoints"
  type        = bool
  default     = true
}

# ============================================================================
# SQS Configuration
# ============================================================================

variable "sqs_max_receive_count" {
  description = "Maximum receive count before message goes to DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.sqs_max_receive_count >= 1 && var.sqs_max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
}

variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds (should be 6x Lambda timeout)"
  type        = number
  default     = 300

  validation {
    condition     = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

# ============================================================================
# Cost Optimization
# ============================================================================

variable "enable_dynamodb_autoscaling" {
  description = "Enable DynamoDB auto-scaling (only for provisioned mode)"
  type        = bool
  default     = false
}

variable "s3_lifecycle_glacier_days" {
  description = "Days before transitioning S3 objects to Glacier"
  type        = number
  default     = 90

  validation {
    condition     = var.s3_lifecycle_glacier_days >= 30
    error_message = "Glacier transition must be at least 30 days."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Days before expiring S3 objects"
  type        = number
  default     = 7 #for testing. 365 for default.

  validation {
    condition     = var.s3_lifecycle_expiration_days >= var.s3_lifecycle_glacier_days
    error_message = "Expiration must be after Glacier transition."
  }
}

# ============================================================================
# Alerting & Notifications
# ============================================================================

variable "alert_email_addresses" {
  description = "List of email addresses for fraud alerts"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid."
  }
}

variable "enable_slack_notifications" {
  description = "Enable Slack notifications for high-risk alerts"
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (store in AWS Secrets Manager in production)"
  type        = string
  default     = ""
  sensitive   = true
}

# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Feature Flags
# ============================================================================

variable "enable_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery (recommended for production)"
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services (enhanced security)"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Enable AWS WAF for API Gateway"
  type        = bool
  default     = false
}
