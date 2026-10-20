variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name (e.g. proj06-dev)."
}

variable "lambda_ingestion_name" {
  type = string
}

variable "lambda_ingestion_arn" {
  type = string
}