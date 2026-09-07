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
  name = "proj06-lambda-ingestion-role"

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
  function_name    = "ingestion_lambda_function"
  role             = aws_iam_role.ingestion.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_ingest.output_base64sha256

  runtime = "nodejs22.x"
  timeout = 10

  environment {
    variables = {
      QUEUE_URL = var.sqs_url
    }
  }

  tags = {
    Project = "proj06"
  }
}

resource "aws_cloudwatch_log_group" "ingest_logs" {
  name = "/aws/lambda/${aws_lambda_function.ingestion.function_name}"

  retention_in_days = 30
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
  name = "proj06-lambda-processor-role"

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
  function_name    = "processor_lambda_function"
  role             = aws_iam_role.processor.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_processor.output_base64sha256

  runtime = "nodejs22.x"
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
}

resource "aws_lambda_event_source_mapping" "process_sqs" {
  event_source_arn = var.sqs_arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 5
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
  name = "proj06-lambda-notifier-role"

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
  function_name    = "notifier_lambda_function"
  role             = aws_iam_role.notifier.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_notifier.output_base64sha256

  runtime = "nodejs22.x"
  timeout = 10

  tags = {
    Project = "proj06"
  }
}
