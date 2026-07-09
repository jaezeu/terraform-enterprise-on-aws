# Outputs of the infra layer (cluster, endpoints, IRSA roles, fqdn). Requires
# remote state sharing to be enabled on the tfe-hvd-eks-infra workspace.
data "terraform_remote_state" "infra" {
  backend = "remote"

  config = {
    organization = "jaz-hashi"
    workspaces = {
      name = "tfe-hvd-eks-infra"
    }
  }
}

data "aws_region" "current" {}

# try(): if the infra workspace was already destroyed its outputs are gone,
# but this layer must still be able to plan its own destroy (deletes use
# values recorded in state, not these expressions).
locals {
  infra_outputs = data.terraform_remote_state.infra.outputs
  infra_exists  = can(local.infra_outputs.eks_cluster_name)
  infra = {
    eks_cluster_name         = try(local.infra_outputs.eks_cluster_name, "unused")
    tfe_fqdn                 = try(local.infra_outputs.tfe_fqdn, "unused")
    tfe_irsa_role_arn        = try(local.infra_outputs.tfe_irsa_role_arn, "unused")
    public_subnet_ids        = try(local.infra_outputs.public_subnet_ids, [])
    tfe_lb_security_group_id = try(local.infra_outputs.tfe_lb_security_group_id, "unused")
    tfe_database_host        = try(local.infra_outputs.tfe_database_host, "unused")
    s3_bucket_name           = try(local.infra_outputs.s3_bucket_name, "unused")
    redis_primary_endpoint   = try(local.infra_outputs.redis_primary_endpoint, "unused")
  }
}

# Secret VALUES consumed by the Helm install (kubernetes secrets + CA bundle).
# The run role needs secretsmanager:GetSecretValue on <secret_prefix>/*.
locals {
  tfe_secret_value_names = {
    license             = "tfe-license"
    encryption_password = "tfe-encryption-password"
    database_password   = "tfe-database-password"
    redis_password      = "tfe-redis-password"
    tls_cert            = "tfe-tls-cert"
    tls_privkey         = "tfe-tls-privkey"
    tls_ca_bundle       = "tfe-tls-ca-bundle"
  }
}

data "aws_secretsmanager_secret_version" "tfe" {
  for_each  = local.tfe_secret_value_names
  secret_id = "${var.secret_prefix}/${each.value}"
}

# count-gated: these lookups fail hard when the cluster is gone, so skip them
# entirely once the infra workspace no longer exports it (the providers fall
# back to placeholder endpoints — see provider.tf).
data "aws_eks_cluster" "tfe" {
  count = local.infra_exists ? 1 : 0
  name  = local.infra.eks_cluster_name
}

data "aws_eks_cluster_auth" "tfe" {
  count = local.infra_exists ? 1 : 0
  name  = local.infra.eks_cluster_name
}
