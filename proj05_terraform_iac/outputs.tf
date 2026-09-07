output "vpc_id" {
  description = "ID of the VPC created for proj05."
  value       = module.vpc.vpc_id
}

output "load_balancer_dns" {
  description = "Public DNS name of the Application Load Balancer."
  value       = module.compute.load_balancer_dns
}

output "backend_state" {
  description = "Location of the remote Terraform state (S3 bucket/key) used for this deployment."
  value       = "s3://shinado-proj05-private-bucket/proj05/terraform.tfstate"
}
