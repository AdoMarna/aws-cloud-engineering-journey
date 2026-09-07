# Backend blocks cannot reference variables or locals (Terraform evaluates
# them before any input variable is resolved), so the region here must stay
# a literal. It has to match var.aws_region's value for the environment
# actually being deployed. Keep it in sync with scripts/bootstrap_backend.sh.
terraform {
  backend "s3" {
    bucket         = "shinado-proj05-private-bucket"
    key            = "proj05/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "shinado-proj05-table"
  }
}