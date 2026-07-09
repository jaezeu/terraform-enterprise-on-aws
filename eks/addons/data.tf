# Outputs of the infra layer. Requires remote state sharing to be enabled on
# the tfe-hvd-eks-infra workspace for this workspace. Reads authenticate
# automatically inside HCP Terraform runs.
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
    eks_cluster_name                = try(local.infra_outputs.eks_cluster_name, "unused")
    vpc_id                          = try(local.infra_outputs.vpc_id, "unused")
    aws_lb_controller_irsa_role_arn = try(local.infra_outputs.aws_lb_controller_irsa_role_arn, "unused")
    external_dns_irsa_role_arn      = try(local.infra_outputs.external_dns_irsa_role_arn, "unused")
    route53_zone_name               = try(local.infra_outputs.route53_zone_name, "unused")
  }
}

# count-gated: these lookups fail hard when the cluster is gone, so skip them
# entirely once the infra workspace no longer exports it (the provider falls
# back to placeholder endpoints — see provider.tf).
data "aws_eks_cluster" "tfe" {
  count = local.infra_exists ? 1 : 0
  name  = local.infra.eks_cluster_name
}

data "aws_eks_cluster_auth" "tfe" {
  count = local.infra_exists ? 1 : 0
  name  = local.infra.eks_cluster_name
}
