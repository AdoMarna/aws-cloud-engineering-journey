terraform {
  required_version = ">= 1.10"

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

locals {
  # Every resource name is prefixed so dev and prod can coexist in one account.
  name_prefix = "proj06-${var.environment}"
}

# Each environment has its own state (S3 key "env:/<workspace>/..."). Refuse to
# plan if the selected workspace doesn't match the tfvars being applied.
resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = terraform.workspace == var.environment
      error_message = "Workspace \"${terraform.workspace}\" does not match environment \"${var.environment}\". Run: terraform workspace select -or-create ${var.environment}"
    }
  }
}

module "api_gateway" {
  source = "./modules/api_gateway"

  name_prefix = local.name_prefix

  lambda_ingestion_arn  = module.lambda.lambda_ingestion_arn
  lambda_ingestion_name = module.lambda.lambda_ingestion_name
}

module "sqs" {
  source = "./modules/sqs"

  name_prefix = local.name_prefix
}

module "dynamodb" {
  source = "./modules/dynamodb"

  name_prefix = local.name_prefix
}

module "eventbridge" {
  source = "./modules/eventbridge"

  name_prefix = local.name_prefix
}

module "lambda" {
  source = "./modules/lambda"

  name_prefix = local.name_prefix

  sqs_arn = module.sqs.sqs_arn
  sqs_url = module.sqs.sqs_url

  dynamodb_name = module.dynamodb.dynamodb_name
  dynamodb_arn  = module.dynamodb.dynamodb_arn

  event_bus_name = module.eventbridge.event_bus_name
  event_bus_arn  = module.eventbridge.event_bus_arn
}

resource "aws_cloudwatch_event_rule" "order_processed" {
  name           = "${local.name_prefix}-order-processed"
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