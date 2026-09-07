resource "aws_cloudwatch_event_bus" "orders_event_bus" {
  name = "orders-event-bus"

  tags = {
    Project = "proj06"
  }
}
