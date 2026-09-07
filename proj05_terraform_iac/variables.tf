variable "aws_region" {
  type        = string
  description = "AWS region to deploy the stack into."
  default     = "eu-west-3"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. eu-west-3)."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "Primary IPv4 CIDR block for the VPC (e.g. 10.0.0.0/16)."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "pub_sub_one_cidr" {
  type        = string
  description = "CIDR block for the public subnet in the first availability zone."

  validation {
    condition     = can(cidrhost(var.pub_sub_one_cidr, 0))
    error_message = "pub_sub_one_cidr must be a valid IPv4 CIDR block."
  }
}

variable "pub_sub_two_cidr" {
  type        = string
  description = "CIDR block for the public subnet in the second availability zone."

  validation {
    condition     = can(cidrhost(var.pub_sub_two_cidr, 0))
    error_message = "pub_sub_two_cidr must be a valid IPv4 CIDR block."
  }
}

variable "priv_sub_one_cidr" {
  type        = string
  description = "CIDR block for the private (NAT-routed) subnet in the first availability zone."

  validation {
    condition     = can(cidrhost(var.priv_sub_one_cidr, 0))
    error_message = "priv_sub_one_cidr must be a valid IPv4 CIDR block."
  }
}

variable "priv_sub_two_cidr" {
  type        = string
  description = "CIDR block for the private (NAT-routed) subnet in the second availability zone."

  validation {
    condition     = can(cidrhost(var.priv_sub_two_cidr, 0))
    error_message = "priv_sub_two_cidr must be a valid IPv4 CIDR block."
  }
}

variable "iso_sub_one_cidr" {
  type        = string
  description = "CIDR block for the isolated (no-route-out) subnet in the first availability zone."

  validation {
    condition     = can(cidrhost(var.iso_sub_one_cidr, 0))
    error_message = "iso_sub_one_cidr must be a valid IPv4 CIDR block."
  }
}

variable "iso_sub_two_cidr" {
  type        = string
  description = "CIDR block for the isolated (no-route-out) subnet in the second availability zone."

  validation {
    condition     = can(cidrhost(var.iso_sub_two_cidr, 0))
    error_message = "iso_sub_two_cidr must be a valid IPv4 CIDR block."
  }
}

variable "pub_route_cidr" {
  type        = string
  description = "Destination CIDR routed through the NAT Gateways in the private route tables (e.g. 0.0.0.0/0)."

  validation {
    condition     = can(cidrhost(var.pub_route_cidr, 0))
    error_message = "pub_route_cidr must be a valid IPv4 CIDR block."
  }
}
