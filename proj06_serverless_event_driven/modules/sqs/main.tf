resource "aws_sqs_queue" "orders_dlq" {
  name = "${var.name_prefix}-orders-dlq"

  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true

  tags = {
    Project = "proj06"
  }
}

resource "aws_sqs_queue" "orders" {
  name = "${var.name_prefix}-orders"

  message_retention_seconds = 345600 # 4 days
  sqs_managed_sse_enabled   = true
  delay_seconds             = 0
  receive_wait_time_seconds = 20
  # >= 6x timeout Lambda processor (30s) : recommandé pour l'Event Source Mapping
  visibility_timeout_seconds = 180

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Project = "proj06"
  }
}
