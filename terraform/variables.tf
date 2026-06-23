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
  description = "Environment name"
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
  default     = "ca-central-1"
}

variable "additional_tags" {
  description = "Additional tags applied to all supported resources"
  type        = map(string)
  default     = {}
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
  description = "Memory allocation for the transaction processor Lambda in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.transaction_processor_memory >= 128 && var.transaction_processor_memory <= 10240
    error_message = "Memory must be between 128 MB and 10240 MB."
  }
}

variable "transaction_processor_timeout" {
  description = "Timeout for the transaction processor Lambda in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.transaction_processor_timeout >= 3 && var.transaction_processor_timeout <= 900
    error_message = "Timeout must be between 3 and 900 seconds."
  }
}

variable "fraud_detector_memory" {
  description = "Memory allocation for the fraud detector Lambda in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.fraud_detector_memory >= 128 && var.fraud_detector_memory <= 10240
    error_message = "Memory must be between 128 MB and 10240 MB."
  }
}

variable "fraud_detector_timeout" {
  description = "Timeout for the fraud detector Lambda in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.fraud_detector_timeout >= 3 && var.fraud_detector_timeout <= 900
    error_message = "Timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for each Lambda function (-1 for unreserved)"
  type        = number
  default     = -1

  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "Reserved concurrency must be -1 or greater."
  }
}

variable "api_handler_memory" {
  description = "Memory allocation for the API handler Lambda in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.api_handler_memory >= 128 && var.api_handler_memory <= 10240
    error_message = "Memory must be between 128 MB and 10240 MB."
  }
}

variable "api_handler_timeout" {
  description = "Timeout for the API handler Lambda in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.api_handler_timeout >= 3 && var.api_handler_timeout <= 900
    error_message = "Timeout must be between 3 and 900 seconds."
  }
}

# ============================================================================
# Monitoring
# ============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30

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

variable "enable_alarm_notifications" {
  description = "Send CloudWatch alarm state changes to the fraud alert SNS topic"
  type        = bool
  default     = false
}

variable "alarm_period_seconds" {
  description = "CloudWatch alarm evaluation period in seconds"
  type        = number
  default     = 300

  validation {
    condition     = contains([10, 30, 60, 300, 900], var.alarm_period_seconds)
    error_message = "Alarm period must be one of 10, 30, 60, 300, or 900 seconds."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods used when evaluating CloudWatch alarms"
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

variable "lambda_duration_alarm_threshold_percent" {
  description = "Percent of each Lambda timeout used for duration alarms"
  type        = number
  default     = 80

  validation {
    condition     = var.lambda_duration_alarm_threshold_percent > 0 && var.lambda_duration_alarm_threshold_percent <= 100
    error_message = "Lambda duration alarm threshold percent must be greater than 0 and at most 100."
  }
}

# ============================================================================
# API Configuration
# ============================================================================

variable "api_allowed_origins" {
  description = "Allowed CORS origins for the HTTP API"
  type        = list(string)
  default     = ["*"]
}

# ============================================================================
# Fraud Detection Configuration
# ============================================================================

variable "fraud_risk_threshold" {
  description = "Risk score threshold for fraud alerts"
  type        = number
  default     = 75

  validation {
    condition     = var.fraud_risk_threshold >= 0 && var.fraud_risk_threshold <= 100
    error_message = "Fraud risk threshold must be between 0 and 100."
  }
}

variable "velocity_check_window_minutes" {
  description = "Time window for transaction velocity checks"
  type        = number
  default     = 60

  validation {
    condition     = var.velocity_check_window_minutes > 0 && var.velocity_check_window_minutes <= 1440
    error_message = "Velocity check window must be between 1 and 1440 minutes."
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
  description = "Transaction amount that triggers additional risk scoring"
  type        = number
  default     = 1000.00

  validation {
    condition     = var.suspicious_amount_threshold >= 0
    error_message = "Suspicious amount threshold must be non-negative."
  }
}

variable "alert_email_addresses" {
  description = "Email addresses subscribed to high-risk fraud alert notifications"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.alert_email_addresses :
      can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", email))
    ])
    error_message = "All alert email addresses must be valid email addresses."
  }
}

# ============================================================================
# SQS Configuration
# ============================================================================

variable "sqs_max_receive_count" {
  description = "Maximum receive count before a message is sent to a dead-letter queue"
  type        = number
  default     = 3

  validation {
    condition     = var.sqs_max_receive_count >= 1 && var.sqs_max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
}

variable "sqs_visibility_timeout" {
  description = "Transaction queue visibility timeout in seconds"
  type        = number
  default     = 180

  validation {
    condition     = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds."
  }
}

# ============================================================================
# Storage Configuration
# ============================================================================

variable "enable_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery"
  type        = bool
  default     = false
}

variable "s3_lifecycle_glacier_days" {
  description = "Days before transitioning audit logs to Glacier"
  type        = number
  default     = 90

  validation {
    condition     = var.s3_lifecycle_glacier_days >= 30
    error_message = "Glacier transition must be at least 30 days."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Days before expiring audit logs"
  type        = number
  default     = 365

  validation {
    condition     = var.s3_lifecycle_expiration_days >= 30
    error_message = "Expiration must be at least 30 days."
  }
}
