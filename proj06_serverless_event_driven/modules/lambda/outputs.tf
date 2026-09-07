output "lambda_ingestion_name" {
  value = aws_lambda_function.ingestion.function_name
}

output "lambda_ingestion_arn" {
  value = aws_lambda_function.ingestion.invoke_arn
}

output "lambda_notifier_name" {
  value = aws_lambda_function.notifier.function_name
}

output "lambda_notifier_arn" {
  value = aws_lambda_function.notifier.arn
}