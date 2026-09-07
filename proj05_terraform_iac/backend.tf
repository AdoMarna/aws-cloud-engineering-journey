terraform {
  backend "s3" {
    bucket         = "shinado-proj05-private-bucket"
    key            = "proj05/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "shinado-proj05-table"
  }
}