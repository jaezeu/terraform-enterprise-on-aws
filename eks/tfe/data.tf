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

data "aws_eks_cluster" "tfe" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

data "aws_eks_cluster_auth" "tfe" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}
