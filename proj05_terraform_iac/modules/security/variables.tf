variable "vpc_id" {
  type        = string
  description = "ID of the VPC the security groups and NACL are attached to."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (starting with \"vpc-\")."
  }
}

variable "public_subnet_az1_id" {
  type        = string
  description = "ID of the public subnet in the first availability zone."

  validation {
    condition     = can(regex("^subnet-", var.public_subnet_az1_id))
    error_message = "public_subnet_az1_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "public_subnet_az2_id" {
  type        = string
  description = "ID of the public subnet in the second availability zone."

  validation {
    condition     = can(regex("^subnet-", var.public_subnet_az2_id))
    error_message = "public_subnet_az2_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "private_subnet_az1_id" {
  type        = string
  description = "ID of the private subnet in the first availability zone."

  validation {
    condition     = can(regex("^subnet-", var.private_subnet_az1_id))
    error_message = "private_subnet_az1_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "private_subnet_az2_id" {
  type        = string
  description = "ID of the private subnet in the second availability zone."

  validation {
    condition     = can(regex("^subnet-", var.private_subnet_az2_id))
    error_message = "private_subnet_az2_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "isolated_subnet_az1_id" {
  type        = string
  description = "ID of the isolated subnet in the first availability zone."

  validation {
    condition     = can(regex("^subnet-", var.isolated_subnet_az1_id))
    error_message = "isolated_subnet_az1_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "isolated_subnet_az2_id" {
  type        = string
  description = "ID of the isolated subnet in the second availability zone."

  validation {
    condition     = can(regex("^subnet-", var.isolated_subnet_az2_id))
    error_message = "isolated_subnet_az2_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}
