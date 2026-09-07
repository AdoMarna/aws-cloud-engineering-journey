variable "aws_region" {
  type        = string
  description = "AWS region to deploy the stack into."
  default     = "eu-west-3"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. eu-west-3)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name, applied as a tag on every resource (e.g. dev, prod)."

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}
