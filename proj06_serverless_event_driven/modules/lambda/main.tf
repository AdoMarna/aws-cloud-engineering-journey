locals {
  ingest_function_name    = "${var.name_prefix}-ingest"
  processor_function_name = "${var.name_prefix}-processor"
  notifier_function_name  = "${var.name_prefix}-notifier"
}

# Log groups are created before the functions: otherwise Lambda creates them
# itself on first invocation, with infinite retention and outside of Terraform.
resource "aws_cloudwatch_log_group" "ingest_logs" {
  name              = "/aws/lambda/${local.ingest_function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "processor_logs" {
  name              = "/aws/lambda/${local.processor_function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "notifier_logs" {
  name              = "/aws/lambda/${local.notifier_function_name}"
  retention_in_days = 30
}


# ============================================================
# LAMBDA — INGESTION
# ============================================================
# API Gateway → Ingestion Lambda → SQS
# ============================================================

data "archive_file" "lambda_ingest" {
  type        = "zip"
  source_dir  = "${path.root}/src/ingest"
  output_path = "${path.root}/build/ingest.zip"
  excludes    = ["*.zip"]
}

resource "aws_iam_role" "ingestion" {
  name = "${var.name_prefix}-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ingestion_logs" {
  role       = aws_iam_role.ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ingestion_inline" {
  role = aws_iam_role.ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = var.sqs_arn
    }]
  })
}

resource "aws_lambda_function" "ingestion" {
  filename         = data.archive_file.lambda_ingest.output_path
  function_name    = local.ingest_function_name
  role             = aws_iam_role.ingestion.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_ingest.output_base64sha256

  runtime = "nodejs24.x"
  timeout = 10

  environment {
    variables = {
      QUEUE_URL = var.sqs_url
    }
  }

  tags = {
    Project = "proj06"
  }

  depends_on = [aws_cloudwatch_log_group.ingest_logs]
}

# ============================================================
# LAMBDA — PROCESSOR
# ============================================================
# SQS → Processor Lambda → DynamoDB
#                         → EventBridge
# ============================================================

data "archive_file" "lambda_processor" {
  type        = "zip"
  source_dir  = "${path.root}/src/processor"
  output_path = "${path.root}/build/processor.zip"
  excludes    = ["*.zip"]
}

resource "aws_iam_role" "processor" {
  name = "${var.name_prefix}-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "processor_logs" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "processor_inline" {
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Required by the SQS event source mapping (polling on the function's behalf)
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_arn
      },
      {
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = var.dynamodb_arn
      },
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = var.event_bus_arn
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.lambda_processor.output_path
  function_name    = local.processor_function_name
  role             = aws_iam_role.processor.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_processor.output_base64sha256

  runtime = "nodejs24.x"
  timeout = 30

  environment {
    variables = {
      TABLE_NAME     = var.dynamodb_name
      EVENT_BUS_NAME = var.event_bus_name
    }
  }

  tags = {
    Project = "proj06"
  }

  depends_on = [aws_cloudwatch_log_group.processor_logs]
}

resource "aws_lambda_event_source_mapping" "process_sqs" {
  event_source_arn = var.sqs_arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 5

  # The processor returns the IDs of failed messages: only those are retried
  # (and eventually sent to the DLQ), not the whole batch.
  function_response_types = ["ReportBatchItemFailures"]

  # AWS checks the role's SQS permissions when the mapping is created
  depends_on = [aws_iam_role_policy.processor_inline]
}


# ============================================================
# LAMBDA — NOTIFIER
# ============================================================
# EventBridge → Notifier Lambda → Notification
# ============================================================

data "archive_file" "lambda_notifier" {
  type        = "zip"
  source_dir  = "${path.root}/src/notifier"
  output_path = "${path.root}/build/notifier.zip"
  excludes    = ["*.zip"]
}

resource "aws_iam_role" "notifier" {
  name = "${var.name_prefix}-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "notifier_logs" {
  role       = aws_iam_role.notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "notifier" {
  filename         = data.archive_file.lambda_notifier.output_path
  function_name    = local.notifier_function_name
  role             = aws_iam_role.notifier.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_notifier.output_base64sha256

  runtime = "nodejs24.x"
  timeout = 10

  tags = {
    Project = "proj06"
  }

  depends_on = [aws_cloudwatch_log_group.notifier_logs]
}
