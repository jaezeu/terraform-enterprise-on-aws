# Consumed by the addons and tfe layers via terraform_remote_state — enable
# remote state sharing on this workspace (Settings > General) for
# tfe-hvd-eks-addons and tfe-hvd-eks-tfe.

output "eks_cluster_name" {
  description = "Name of the TFE EKS cluster."
  value       = module.tfe_eks.eks_cluster_name
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.tfe_vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (TFE NLB)."
  value       = module.tfe_vpc.public_subnets
}

output "tfe_lb_security_group_id" {
  description = "Security group for the TFE load balancer."
  value       = module.tfe_eks.tfe_lb_security_group_id
}

output "tfe_irsa_role_arn" {
  description = "IRSA role for the TFE service account."
  value       = module.tfe_eks.tfe_irsa_role_arn
}

output "aws_lb_controller_irsa_role_arn" {
  description = "IRSA role for the AWS Load Balancer Controller."
  value       = module.tfe_eks.aws_lb_controller_irsa_role_arn
}

output "external_dns_irsa_role_arn" {
  description = "IRSA role for external-dns."
  value       = aws_iam_role.external_dns_irsa.arn
}

output "tfe_database_host" {
  description = "PostgreSQL endpoint (host:port) for TFE."
  value       = module.tfe_eks.tfe_database_host
}

output "s3_bucket_name" {
  description = "TFE object storage bucket."
  value       = module.tfe_eks.s3_bucket_name
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint."
  value       = module.tfe_eks.elasticache_replication_group_primary_endpoint_address
}

output "tfe_fqdn" {
  description = "FQDN of the TFE instance (single source of truth for downstream layers)."
  value       = var.tfe_fqdn
}

output "route53_zone_name" {
  description = "Hosted zone external-dns manages."
  value       = var.route53_tfe_hosted_zone_name
}

output "tfe_url" {
  description = "HTTPS URL of the TFE instance."
  value       = module.tfe_eks.tfe_url
}
