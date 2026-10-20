resource "aws_cloudwatch_event_bus" "orders_event_bus" {
  name = "${var.name_prefix}-orders-bus"

  tags = {
    Project = "proj06"
  }
}
