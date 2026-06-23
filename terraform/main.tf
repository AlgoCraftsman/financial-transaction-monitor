terraform {
  required_version = ">= 1.6"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Recommended for shared environments:
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "financial-transaction-monitor/terraform.tfstate"
  #   region         = "ca-central-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "Terraform"
      },
      var.additional_tags
    )
  }
}

locals {
  transaction_processor_duration_alarm_ms = (
    var.transaction_processor_timeout * 1000 * var.lambda_duration_alarm_threshold_percent / 100
  )
  fraud_detector_duration_alarm_ms = (
    var.fraud_detector_timeout * 1000 * var.lambda_duration_alarm_threshold_percent / 100
  )
  api_handler_duration_alarm_ms = (
    var.api_handler_timeout * 1000 * var.lambda_duration_alarm_threshold_percent / 100
  )
  alarm_actions = var.enable_alarm_notifications ? [aws_sns_topic.fraud_alerts.arn] : []
}

# ============================================================================
# DynamoDB Tables
# ============================================================================

resource "aws_dynamodb_table" "transactions" {
  name         = "${var.project_name}-transactions-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
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
    name = "risk_level"
    type = "S"
  }

  global_secondary_index {
    name            = "UserIdIndex"
    hash_key        = "user_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "RiskLevelIndex"
    hash_key        = "risk_level"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery || var.environment == "production"
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
    enabled = var.enable_point_in_time_recovery || var.environment == "production"
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-fraud-alerts"
  }
}

# ============================================================================
# SQS Queues
# ============================================================================

resource "aws_sqs_queue" "transaction_dlq" {
  name                      = "${var.project_name}-transactions-dlq-${var.environment}"
  message_retention_seconds = 1209600

  tags = {
    Name = "${var.project_name}-transaction-dlq"
  }
}

resource "aws_sqs_queue" "transaction_queue" {
  name                       = "${var.project_name}-transactions-${var.environment}"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.transaction_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = {
    Name = "${var.project_name}-transaction-queue"
  }
}

resource "aws_sqs_queue" "fraud_alert_dlq" {
  name                      = "${var.project_name}-fraud-alerts-dlq-${var.environment}"
  message_retention_seconds = 1209600

  tags = {
    Name = "${var.project_name}-fraud-alert-dlq"
  }
}

resource "aws_sqs_queue" "fraud_alert_queue" {
  name                       = "${var.project_name}-fraud-alerts-${var.environment}"
  visibility_timeout_seconds = var.fraud_detector_timeout * 6
  message_retention_seconds  = 604800
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_alert_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = {
    Name = "${var.project_name}-fraud-alert-queue"
  }
}

# ============================================================================
# SNS Notifications
# ============================================================================

resource "aws_sns_topic" "fraud_alerts" {
  name = "${var.project_name}-fraud-alerts-${var.environment}"

  tags = {
    Name = "${var.project_name}-fraud-alerts-topic"
  }
}

resource "aws_sns_topic_subscription" "fraud_alert_email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.fraud_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ============================================================================
# S3 Bucket
# ============================================================================

resource "aws_s3_bucket" "transaction_logs" {
  bucket = "${var.project_name}-transaction-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-transaction-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  versioning_configuration {
    status = var.environment == "production" ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "transaction_logs" {
  bucket = aws_s3_bucket.transaction_logs.id

  rule {
    id     = "expire-transaction-audit-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = var.s3_lifecycle_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_expiration_days
    }
  }
}

# ============================================================================
# IAM Roles
# ============================================================================

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transaction_processor_lambda" {
  name               = "${var.project_name}-transaction-processor-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-transaction-processor-role"
  }
}

resource "aws_iam_role" "fraud_detector_lambda" {
  name               = "${var.project_name}-fraud-detector-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-fraud-detector-role"
  }
}

resource "aws_iam_role" "api_handler_lambda" {
  name               = "${var.project_name}-api-handler-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-api-handler-role"
  }
}

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
          "dynamodb:Query"
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
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
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
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.fraud_alerts.arn
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
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.fraud_alerts.arn,
          "${aws_dynamodb_table.fraud_alerts.arn}/index/*"
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

resource "aws_iam_role_policy" "api_handler_policy" {
  name = "${var.project_name}-api-handler-policy"
  role = aws_iam_role.api_handler_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.transactions.arn,
          "${aws_dynamodb_table.transactions.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.fraud_alerts.arn,
          "${aws_dynamodb_table.fraud_alerts.arn}/index/*"
        ]
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

resource "aws_iam_role_policy_attachment" "transaction_processor_basic" {
  role       = aws_iam_role.transaction_processor_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fraud_detector_basic" {
  role       = aws_iam_role.fraud_detector_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "api_handler_basic" {
  role       = aws_iam_role.api_handler_lambda.name
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

resource "aws_cloudwatch_log_group" "api_handler" {
  name              = "/aws/lambda/${var.project_name}-api-handler-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-api-handler-logs"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

# ============================================================================
# Lambda Packages
# ============================================================================

data "archive_file" "transaction_processor" {
  type        = "zip"
  source_file = "${path.module}/../lambda-functions/transaction_processor.py"
  output_path = "${path.module}/transaction_processor.zip"
}

data "archive_file" "fraud_detector" {
  type        = "zip"
  source_file = "${path.module}/../lambda-functions/fraud_detector.py"
  output_path = "${path.module}/fraud_detector.zip"
}

data "archive_file" "api_handler" {
  type        = "zip"
  source_file = "${path.module}/../lambda-functions/api_handler.py"
  output_path = "${path.module}/api_handler.zip"
}

# ============================================================================
# Lambda Functions
# ============================================================================

resource "aws_lambda_function" "transaction_processor" {
  function_name                  = "${var.project_name}-transaction-processor-${var.environment}"
  role                           = aws_iam_role.transaction_processor_lambda.arn
  runtime                        = var.lambda_runtime
  handler                        = "transaction_processor.lambda_handler"
  filename                       = data.archive_file.transaction_processor.output_path
  source_code_hash               = data.archive_file.transaction_processor.output_base64sha256
  timeout                        = var.transaction_processor_timeout
  memory_size                    = var.transaction_processor_memory
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  environment {
    variables = {
      TRANSACTIONS_TABLE          = aws_dynamodb_table.transactions.name
      FRAUD_ALERT_QUEUE_URL       = aws_sqs_queue.fraud_alert_queue.url
      S3_BUCKET                   = aws_s3_bucket.transaction_logs.bucket
      FRAUD_RISK_THRESHOLD        = tostring(var.fraud_risk_threshold)
      VELOCITY_WINDOW_MINUTES     = tostring(var.velocity_check_window_minutes)
      MAX_TRANSACTIONS_PER_WINDOW = tostring(var.max_transactions_per_window)
      SUSPICIOUS_AMOUNT_THRESHOLD = tostring(var.suspicious_amount_threshold)
      ENVIRONMENT                 = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.transaction_processor,
    aws_iam_role_policy_attachment.transaction_processor_basic
  ]

  tags = {
    Name = "${var.project_name}-transaction-processor"
  }
}

resource "aws_lambda_function" "fraud_detector" {
  function_name                  = "${var.project_name}-fraud-detector-${var.environment}"
  role                           = aws_iam_role.fraud_detector_lambda.arn
  runtime                        = var.lambda_runtime
  handler                        = "fraud_detector.lambda_handler"
  filename                       = data.archive_file.fraud_detector.output_path
  source_code_hash               = data.archive_file.fraud_detector.output_base64sha256
  timeout                        = var.fraud_detector_timeout
  memory_size                    = var.fraud_detector_memory
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  environment {
    variables = {
      FRAUD_ALERTS_TABLE    = aws_dynamodb_table.fraud_alerts.name
      FRAUD_ALERT_TOPIC_ARN = aws_sns_topic.fraud_alerts.arn
      S3_BUCKET             = aws_s3_bucket.transaction_logs.bucket
      ENVIRONMENT           = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.fraud_detector,
    aws_iam_role_policy_attachment.fraud_detector_basic
  ]

  tags = {
    Name = "${var.project_name}-fraud-detector"
  }
}

resource "aws_lambda_function" "api_handler" {
  function_name                  = "${var.project_name}-api-handler-${var.environment}"
  role                           = aws_iam_role.api_handler_lambda.arn
  runtime                        = var.lambda_runtime
  handler                        = "api_handler.lambda_handler"
  filename                       = data.archive_file.api_handler.output_path
  source_code_hash               = data.archive_file.api_handler.output_base64sha256
  timeout                        = var.api_handler_timeout
  memory_size                    = var.api_handler_memory
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  environment {
    variables = {
      TRANSACTIONS_TABLE = aws_dynamodb_table.transactions.name
      FRAUD_ALERTS_TABLE = aws_dynamodb_table.fraud_alerts.name
      ENVIRONMENT        = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.api_handler,
    aws_iam_role_policy_attachment.api_handler_basic
  ]

  tags = {
    Name = "${var.project_name}-api-handler"
  }
}

resource "aws_lambda_event_source_mapping" "transaction_processor_sqs" {
  event_source_arn        = aws_sqs_queue.transaction_queue.arn
  function_name           = aws_lambda_function.transaction_processor.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_lambda_event_source_mapping" "fraud_detector_sqs" {
  event_source_arn        = aws_sqs_queue.fraud_alert_queue.arn
  function_name           = aws_lambda_function.fraud_detector.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

# ============================================================================
# API Gateway
# ============================================================================

resource "aws_apigatewayv2_api" "monitoring_api" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["GET", "PATCH", "OPTIONS"]
    allow_origins = var.api_allowed_origins
    max_age       = 300
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

resource "aws_apigatewayv2_integration" "api_handler" {
  api_id                 = aws_apigatewayv2_api.monitoring_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.monitoring_api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.api_handler.id}"
}

resource "aws_apigatewayv2_route" "get_transaction" {
  api_id    = aws_apigatewayv2_api.monitoring_api.id
  route_key = "GET /transactions/{transaction_id}"
  target    = "integrations/${aws_apigatewayv2_integration.api_handler.id}"
}

resource "aws_apigatewayv2_route" "get_user_transactions" {
  api_id    = aws_apigatewayv2_api.monitoring_api.id
  route_key = "GET /transactions/user/{user_id}"
  target    = "integrations/${aws_apigatewayv2_integration.api_handler.id}"
}

resource "aws_apigatewayv2_route" "list_alerts" {
  api_id    = aws_apigatewayv2_api.monitoring_api.id
  route_key = "GET /alerts"
  target    = "integrations/${aws_apigatewayv2_integration.api_handler.id}"
}

resource "aws_apigatewayv2_route" "get_alert" {
  api_id    = aws_apigatewayv2_api.monitoring_api.id
  route_key = "GET /alerts/{alert_id}"
  target    = "integrations/${aws_apigatewayv2_integration.api_handler.id}"
}

resource "aws_apigatewayv2_route" "update_alert_status" {
  api_id    = aws_apigatewayv2_api.monitoring_api.id
  route_key = "PATCH /alerts/{alert_id}/status"
  target    = "integrations/${aws_apigatewayv2_integration.api_handler.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.monitoring_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.monitoring_api.execution_arn}/*/*"
}

# ============================================================================
# CloudWatch Alarms
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "transaction_processor_errors" {
  alarm_name          = "${var.project_name}-transaction-processor-errors-${var.environment}"
  alarm_description   = "Transaction processor Lambda has one or more errors."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.transaction_processor.function_name
  }

  tags = {
    Name = "${var.project_name}-transaction-processor-errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "fraud_detector_errors" {
  alarm_name          = "${var.project_name}-fraud-detector-errors-${var.environment}"
  alarm_description   = "Fraud detector Lambda has one or more errors."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.fraud_detector.function_name
  }

  tags = {
    Name = "${var.project_name}-fraud-detector-errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_handler_errors" {
  alarm_name          = "${var.project_name}-api-handler-errors-${var.environment}"
  alarm_description   = "API handler Lambda has one or more errors."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api_handler.function_name
  }

  tags = {
    Name = "${var.project_name}-api-handler-errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "transaction_processor_duration" {
  alarm_name          = "${var.project_name}-transaction-processor-duration-${var.environment}"
  alarm_description   = "Transaction processor Lambda duration is near its configured timeout."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = local.transaction_processor_duration_alarm_ms
  treat_missing_data  = "notBreaching"
  unit                = "Milliseconds"

  dimensions = {
    FunctionName = aws_lambda_function.transaction_processor.function_name
  }

  tags = {
    Name = "${var.project_name}-transaction-processor-duration"
  }
}

resource "aws_cloudwatch_metric_alarm" "fraud_detector_duration" {
  alarm_name          = "${var.project_name}-fraud-detector-duration-${var.environment}"
  alarm_description   = "Fraud detector Lambda duration is near its configured timeout."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = local.fraud_detector_duration_alarm_ms
  treat_missing_data  = "notBreaching"
  unit                = "Milliseconds"

  dimensions = {
    FunctionName = aws_lambda_function.fraud_detector.function_name
  }

  tags = {
    Name = "${var.project_name}-fraud-detector-duration"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_handler_duration" {
  alarm_name          = "${var.project_name}-api-handler-duration-${var.environment}"
  alarm_description   = "API handler Lambda duration is near its configured timeout."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = local.api_handler_duration_alarm_ms
  treat_missing_data  = "notBreaching"
  unit                = "Milliseconds"

  dimensions = {
    FunctionName = aws_lambda_function.api_handler.function_name
  }

  tags = {
    Name = "${var.project_name}-api-handler-duration"
  }
}

resource "aws_cloudwatch_metric_alarm" "transaction_dlq_messages" {
  alarm_name          = "${var.project_name}-transaction-dlq-messages-${var.environment}"
  alarm_description   = "Transaction dead-letter queue has visible messages."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.transaction_dlq.name
  }

  tags = {
    Name = "${var.project_name}-transaction-dlq-messages"
  }
}

resource "aws_cloudwatch_metric_alarm" "fraud_alert_dlq_messages" {
  alarm_name          = "${var.project_name}-fraud-alert-dlq-messages-${var.environment}"
  alarm_description   = "Fraud alert dead-letter queue has visible messages."
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.fraud_alert_dlq.name
  }

  tags = {
    Name = "${var.project_name}-fraud-alert-dlq-messages"
  }
}

# ============================================================================
# CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.project_name}-${var.environment}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda invocations and errors"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.transaction_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", aws_lambda_function.fraud_detector.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", aws_lambda_function.api_handler.function_name],
            [".", "Errors", ".", "."]
          ]
          stat   = "Sum"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Queue depth"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.transaction_queue.name],
            [".", ".", ".", aws_sqs_queue.fraud_alert_queue.name],
            [".", ".", ".", aws_sqs_queue.transaction_dlq.name],
            [".", ".", ".", aws_sqs_queue.fraud_alert_dlq.name]
          ]
          stat   = "Maximum"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda duration"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.transaction_processor.function_name],
            [".", ".", ".", aws_lambda_function.fraud_detector.function_name],
            [".", ".", ".", aws_lambda_function.api_handler.function_name]
          ]
          stat   = "Maximum"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway responses"
          region = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.monitoring_api.id],
            [".", "4xx", ".", "."],
            [".", "5xx", ".", "."]
          ]
          stat   = "Sum"
          period = 300
        }
      }
    ]
  })
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}
