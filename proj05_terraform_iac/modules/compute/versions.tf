terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0"
    }
  }
}
