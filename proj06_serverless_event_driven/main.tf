terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "proj06"
      Environment = var.environment
    }
  }
}

module "api_gateway" {
  source = "./modules/api_gateway"

  lambda_ingestion_arn  = module.lambda.lambda_ingestion_arn
  lambda_ingestion_name = module.lambda.lambda_ingestion_name
}

module "sqs" {
  source = "./modules/sqs"
}

module "dynamodb" {
  source = "./modules/dynamodb"
}

module "eventbridge" {
  source = "./modules/eventbridge"
}

module "lambda" {
  source = "./modules/lambda"

  sqs_arn = module.sqs.sqs_arn
  sqs_url = module.sqs.sqs_url

  dynamodb_name = module.dynamodb.dynamodb_name
  dynamodb_arn  = module.dynamodb.dynamodb_arn

  event_bus_name = module.eventbridge.event_bus_name
  event_bus_arn  = module.eventbridge.event_bus_arn
}

resource "aws_cloudwatch_event_rule" "order_processed" {
  name           = "order-processed-rule"
  event_bus_name = module.eventbridge.event_bus_name

  event_pattern = jsonencode({
    detail-type = ["OrderProcessed"]
  })

  tags = {
    Project = "proj06"
  }
}

resource "aws_cloudwatch_event_target" "notifier" {
  rule           = aws_cloudwatch_event_rule.order_processed.name
  event_bus_name = module.eventbridge.event_bus_name
  arn            = module.lambda.lambda_notifier_arn
}

resource "aws_lambda_permission" "eventbridge_notifier" {
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.lambda_notifier_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_processed.arn
}