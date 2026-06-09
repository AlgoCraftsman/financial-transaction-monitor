

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state management
  # backend "s3" {
  #   bucket         = "terraform-state-bucket"
  #   key            = "transaction-monitoring/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ============================================================================
# DynamoDB Tables
# ============================================================================

# Transactions table - stores all transaction records
resource "aws_dynamodb_table" "transactions" {
  name         = "${var.project_name}-transactions-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # Cost-optimized for variable workloads
  hash_key     = "transaction_id"
  range_key    = "timestamp"

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "risk_score"
    type = "N"
  }

  # GSI for querying by user
  global_secondary_index {
    name            = "UserIdIndex"
    hash_key        = "user_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # GSI for querying high-risk transactions
  global_secondary_index {
    name            = "RiskScoreIndex"
    hash_key        = "risk_score"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.environment == "production"
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-transactions"
  }
}

# Fraud alerts table - stores detected fraud cases
resource "aws_dynamodb_table" "fraud_alerts" {
  name         = "${var.project_name}-fraud-alerts-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "alert_id"
  range_key    = "created_at"

  attribute {
    name = "alert_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "N"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.environment == "production"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-fraud-alerts"
  }
}

# ============================================================================
# SQS Queues
# ============================================================================

# Main transaction processing queue
resource "aws_sqs_queue" "transaction_queue" {
  name                       = "${var.project_name}-transactions-${var.environment}"
  visibility_timeout_seconds = 300     # 5 minutes (6x Lambda timeout)
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling

  # Enable dead-letter queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.transaction_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.project_name}-transaction-queue"
  }
}

# Dead-letter queue for failed transactions
resource "aws_sqs_queue" "transaction_dlq" {
  name                      = "${var.project_name}-transactions-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name = "${var.project_name}-transaction-dlq"
  }
}

# High-priority fraud alert queue
resource "aws_sqs_queue" "fraud_alert_queue" {
  name                       = "${var.project_name}-fraud-alerts-${var.environment}"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 604800 # 7 days
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_alert_dlq.arn
    maxReceiveCount     = 2
  })

  tags = {
    Name = "${var.project_name}-fraud-alert-queue"
  }
}

# Dead-letter queue for failed fraud alerts
resource "aws_sqs_queue" "fraud_alert_dlq" {
  name                      = "${var.project_name}-fraud-alerts-dlq-${var.environment}"
  message_retention_seconds = 1209600

  tags = {
    Name = "${var.project_name}-fraud-alert-dlq"
  }
}

# ============================================================================
# S3 Buckets
# ============================================================================

# Bucket for transaction logs and analytics
resource "aws_s3_bucket" "transaction_logs" {
  bucket = "${var.project_name}-transaction-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-transaction-logs"
  }
}

resource "aws_s3_bucket_versioning" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  versioning_configuration {
    status = var.environment == "production" ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# IAM Roles for Lambda Functions
# ============================================================================

# Transaction processor Lambda role
resource "aws_iam_role" "transaction_processor_lambda" {
  name = "${var.project_name}-transaction-processor-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-transaction-processor-role"
  }
}

# Fraud detector Lambda role
resource "aws_iam_role" "fraud_detector_lambda" {
  name = "${var.project_name}-fraud-detector-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-fraud-detector-role"
  }
}

# ============================================================================
# IAM Policies
# ============================================================================

# Transaction processor policy
resource "aws_iam_role_policy" "transaction_processor_policy" {
  name = "${var.project_name}-transaction-processor-policy"
  role = aws_iam_role.transaction_processor_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.transactions.arn,
          "${aws_dynamodb_table.transactions.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.transaction_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.fraud_alert_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.transaction_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Fraud detector policy
resource "aws_iam_role_policy" "fraud_detector_policy" {
  name = "${var.project_name}-fraud-detector-policy"
  role = aws_iam_role.fraud_detector_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.fraud_alerts.arn,
          "${aws_dynamodb_table.fraud_alerts.arn}/index/*",
          aws_dynamodb_table.transactions.arn,
          "${aws_dynamodb_table.transactions.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.fraud_alert_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.transaction_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "transaction_processor_basic" {
  role       = aws_iam_role.transaction_processor_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fraud_detector_basic" {
  role       = aws_iam_role.fraud_detector_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

resource "aws_cloudwatch_log_group" "transaction_processor" {
  name              = "/aws/lambda/${var.project_name}-transaction-processor-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-transaction-processor-logs"
  }
}

resource "aws_cloudwatch_log_group" "fraud_detector" {
  name              = "/aws/lambda/${var.project_name}-fraud-detector-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-fraud-detector-logs"
  }
}

# ============================================================================
# Lambda Functions
# ============================================================================

resource "aws_lambda_function" "transaction_processor" {
  function_name = "${var.project_name}-transaction-processor-${var.environment}"
  role          = aws_iam_role.transaction_processor_lambda.arn
  runtime       = var.lambda_runtime
  handler       = "transaction_processor.lambda_handler"
  filename      = "${path.module}/../lambda-functions/transaction_processor.zip"
  timeout       = var.transaction_processor_timeout
  memory_size   = var.transaction_processor_memory

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  environment {
    variables = {
      TRANSACTIONS_TABLE             = aws_dynamodb_table.transactions.name
      FRAUD_ALERT_QUEUE_URL          = aws_sqs_queue.fraud_alert_queue.url
      S3_BUCKET                      = aws_s3_bucket.transaction_logs.bucket
      FRAUD_RISK_THRESHOLD           = var.fraud_risk_threshold
      VELOCITY_WINDOW_MINUTES        = var.velocity_check_window_minutes
      MAX_TRANSACTIONS_PER_WINDOW    = var.max_transactions_per_window
      SUSPICIOUS_AMOUNT_THRESHOLD    = var.suspicious_amount_threshold
      ENVIRONMENT                    = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.transaction_processor
  ]

  tags = {
    Name = "${var.project_name}-transaction-processor"
  }
}

resource "aws_lambda_event_source_mapping" "transaction_processor_sqs" {
  event_source_arn        = aws_sqs_queue.transaction_queue.arn
  function_name           = aws_lambda_function.transaction_processor.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}
