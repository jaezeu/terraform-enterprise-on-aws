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

data "aws_eks_cluster" "tfe" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

data "aws_eks_cluster_auth" "tfe" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}
