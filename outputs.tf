output "tfe_url" {
  description = "URL of the TFE instance."
  value       = "https://${var.tfe_fqdn}"
}

output "vpc_id" {
  description = "ID of the VPC created for TFE."
  value       = module.tfe_vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (EC2)."
  value       = module.tfe_vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (load balancer)."
  value       = module.tfe_vpc.public_subnets
}

output "database_subnet_ids" {
  description = "IDs of the database subnets (RDS)."
  value       = module.tfe_vpc.database_subnets
}
