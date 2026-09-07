variable "aws_region" {
  type        = string
  description = "AWS region the stack is deployed into (used for the CloudWatch Logs configuration)."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the ALB and target group are attached to."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (starting with \"vpc-\")."
  }
}

variable "public_subnet_az1_id" {
  type        = string
  description = "ID of the public subnet in the first availability zone, used by the ALB."

  validation {
    condition     = can(regex("^subnet-", var.public_subnet_az1_id))
    error_message = "public_subnet_az1_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "public_subnet_az2_id" {
  type        = string
  description = "ID of the public subnet in the second availability zone, used by the ALB."

  validation {
    condition     = can(regex("^subnet-", var.public_subnet_az2_id))
    error_message = "public_subnet_az2_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "private_subnet_az1_id" {
  type        = string
  description = "ID of the private subnet in the first availability zone, used by the ECS Fargate tasks."

  validation {
    condition     = can(regex("^subnet-", var.private_subnet_az1_id))
    error_message = "private_subnet_az1_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "private_subnet_az2_id" {
  type        = string
  description = "ID of the private subnet in the second availability zone, used by the ECS Fargate tasks."

  validation {
    condition     = can(regex("^subnet-", var.private_subnet_az2_id))
    error_message = "private_subnet_az2_id must be a valid subnet ID (starting with \"subnet-\")."
  }
}

variable "sg_alb_id" {
  type        = string
  description = "ID of the security group attached to the ALB."

  validation {
    condition     = can(regex("^sg-", var.sg_alb_id))
    error_message = "sg_alb_id must be a valid security group ID (starting with \"sg-\")."
  }
}

variable "sg_app_id" {
  type        = string
  description = "ID of the security group attached to the ECS Fargate tasks."

  validation {
    condition     = can(regex("^sg-", var.sg_app_id))
    error_message = "sg_app_id must be a valid security group ID (starting with \"sg-\")."
  }
}

variable "sg_db_id" {
  type        = string
  description = "ID of the security group attached to the database tier."

  validation {
    condition     = can(regex("^sg-", var.sg_db_id))
    error_message = "sg_db_id must be a valid security group ID (starting with \"sg-\")."
  }
}
