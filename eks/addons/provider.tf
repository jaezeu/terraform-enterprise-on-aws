terraform {
  required_version = ">= 1.15.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
  cloud {
    organization = "jaz-hashi"
    workspaces {
      name = "tfe-hvd-eks-addons"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

# Authenticates to the infra-layer cluster as the HCP TF OIDC run role, which
# the HVD module granted AmazonEKSClusterAdminPolicy via an EKS access entry.
# try(): the data sources are absent once the cluster is destroyed (see
# data.tf) — the placeholders keep destroy plans working then.
provider "helm" {
  kubernetes = {
    host                   = try(data.aws_eks_cluster.tfe[0].endpoint, "https://cluster-gone.invalid")
    cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.tfe[0].certificate_authority[0].data), "")
    token                  = try(data.aws_eks_cluster_auth.tfe[0].token, "")
  }
}
