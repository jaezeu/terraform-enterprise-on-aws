output "api_url" {
  description = "Public Kubernetes API endpoint."
  value       = "https://api.${local.cluster_domain}:6443"
}

output "console_url" {
  description = "Web console (resolves once the config layer creates *.apps DNS)."
  value       = "https://console-openshift-console.apps.${local.cluster_domain}"
}

output "infra_id" {
  description = "Installer infrastructure ID (resource name prefix / cluster tag)."
  value       = var.infra_id
}

output "cluster_domain" {
  description = "Cluster DNS domain (<cluster_name>.<base_domain>)."
  value       = local.cluster_domain
}

output "vpc_id" {
  description = "ID of the cluster VPC."
  value       = module.vpc.vpc_id
}

output "base_domain_zone_id" {
  description = "Public zone id — the config layer creates *.apps here."
  value       = try(data.aws_route53_zone.base[0].zone_id, null)
}

output "private_zone_id" {
  description = "Cluster private zone id — the config layer creates *.apps here too, so pods and nodes can resolve routes."
  value       = aws_route53_zone.cluster_private.zone_id
}

output "bootstrap_public_ip" {
  description = "SSH here (core@) with ocp-ssh-key while bootstrapping."
  value       = var.bootstrap_enabled ? aws_instance.bootstrap[0].public_ip : null
}

# --- consumed by the tfe layer ------------------------------------------------
output "base_domain" {
  description = "Public base domain (the wildcard TLS cert covers *.<base_domain>)."
  value       = var.base_domain
}

output "private_subnet_ids" {
  description = "Private subnets — the tfe layer places RDS/ElastiCache here."
  value       = module.vpc.private_subnets
}

output "vpc_cidr" {
  description = "VPC CIDR — the tfe layer scopes RDS/Redis ingress to it."
  value       = module.vpc.vpc_cidr_block
}

output "worker_role_name" {
  description = "Worker node IAM role — the tfe layer grants it access to the TFE app S3 bucket (pods reach IMDS via the imds-proxy, so node-role credentials are what TFE uses for S3)."
  value       = aws_iam_role.node["worker"].name
}
