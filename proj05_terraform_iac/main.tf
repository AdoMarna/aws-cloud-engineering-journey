terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3"
}

data "aws_ecr_authorization_token" "ecr" {}

provider "docker" {
  host = "unix:///var/run/docker.sock"

  registry_auth {
    address  = data.aws_ecr_authorization_token.ecr.proxy_endpoint
    username = data.aws_ecr_authorization_token.ecr.user_name
    password = data.aws_ecr_authorization_token.ecr.password
  }
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr          = var.vpc_cidr
  pub_sub_one_cidr  = var.pub_sub_one_cidr
  pub_sub_two_cidr  = var.pub_sub_two_cidr
  priv_sub_one_cidr = var.priv_sub_one_cidr
  priv_sub_two_cidr = var.priv_sub_two_cidr
  iso_sub_one_cidr  = var.iso_sub_one_cidr
  iso_sub_two_cidr  = var.iso_sub_two_cidr
  pub_route_cidr    = var.pub_route_cidr
}

module "security" {
  source = "./modules/security"

  vpc_id                 = module.vpc.vpc_id
  public_subnet_az1_id   = module.vpc.public_subnet_az1_id
  public_subnet_az2_id   = module.vpc.public_subnet_az2_id
  private_subnet_az1_id  = module.vpc.private_subnet_az1_id
  private_subnet_az2_id  = module.vpc.private_subnet_az2_id
  isolated_subnet_az1_id = module.vpc.isolated_subnet_az1_id
  isolated_subnet_az2_id = module.vpc.isolated_subnet_az2_id
}

module "compute" {
  source = "./modules/compute"

  providers = {
    aws    = aws
    docker = docker
  }

  vpc_id                = module.vpc.vpc_id
  public_subnet_az1_id  = module.vpc.public_subnet_az1_id
  public_subnet_az2_id  = module.vpc.public_subnet_az2_id
  private_subnet_az1_id = module.vpc.private_subnet_az1_id
  private_subnet_az2_id = module.vpc.private_subnet_az2_id

  sg_alb_id = module.security.sg_alb_id
  sg_app_id = module.security.sg_app_id
  sg_db_id  = module.security.sg_db_id
}
