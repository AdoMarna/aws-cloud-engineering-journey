output "sqs_arn" {
  value = aws_sqs_queue.orders.arn
}

output "sqs_url" {
  value = aws_sqs_queue.orders.url
}