variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name (e.g. proj06-dev)."
}

variable "sqs_arn" {
  type = string
}

variable "sqs_url" {
  type = string
}

variable "dynamodb_name" {
  type = string
}

variable "dynamodb_arn" {
  type = string
}

variable "event_bus_name" {
  type = string
}

variable "event_bus_arn" {
  type = string
}