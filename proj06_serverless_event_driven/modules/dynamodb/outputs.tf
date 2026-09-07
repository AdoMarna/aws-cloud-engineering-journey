output "dynamodb_name" {
  value = aws_dynamodb_table.orders_table.name
}

output "dynamodb_arn" {
  value = aws_dynamodb_table.orders_table.arn
}