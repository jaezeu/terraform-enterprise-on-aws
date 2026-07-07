data "aws_availability_zones" "available" {
  state = "available"
}

# Resolve the module's secret ARNs by name from the shared `secret_prefix` —
# metadata only (the module reads the values itself for RDS/ElastiCache).
locals {
  tfe_secret_names = {
    database_password = "tfe-database-password"
    redis_password    = "tfe-redis-password"
  }
}

data "aws_secretsmanager_secret" "tfe" {
  for_each = local.tfe_secret_names
  name     = "${var.secret_prefix}/${each.value}"
}

# Used to build the external-dns IRSA trust policy. depends_on defers this
# read to apply time while the cluster has pending changes — without it, the
# name is already known at plan time (derived from input vars), so Terraform
# would try to read the not-yet-created cluster during plan and fail.
data "aws_eks_cluster" "tfe" {
  name = module.tfe_eks.eks_cluster_name

  depends_on = [module.tfe_eks]
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.tfe.identity[0].oidc[0].issuer
}

data "aws_route53_zone" "tfe" {
  name         = var.route53_tfe_hosted_zone_name
  private_zone = false
}
