output "api_endpoint" {
  description = "Base invoke URL of the HTTP API (POST /orders is appended by clients)."
  value       = module.api_gateway.api_endpoint
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing processed orders."
  value       = module.dynamodb.dynamodb_name
}

output "sqs_queue_url" {
  description = "URL of the main SQS orders queue."
  value       = module.sqs.sqs_url
}

output "event_bus_name" {
  description = "Name of the EventBridge custom event bus used for order fan-out."
  value       = module.eventbridge.event_bus_name
}

output "backend_state" {
  description = "Location of the remote Terraform state (S3 bucket/key) used for this deployment."
  value       = "s3://proj06-bucket/proj06/terraform.tfstate"
}
