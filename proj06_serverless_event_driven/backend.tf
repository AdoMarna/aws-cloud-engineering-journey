# Backend blocks cannot reference variables or locals (Terraform evaluates
# them before any input variable is resolved), so the region here must stay
# a literal. It has to match var.aws_region's value for the environment
# actually being deployed. Keep it in sync with ../bootstrap/bootstrap.sh.
terraform {
  backend "s3" {
    bucket       = "proj06-bucket"
    key          = "proj06/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}