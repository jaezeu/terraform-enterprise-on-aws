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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
  cloud {
    organization = "jaz-hashi"
    workspaces {
      name = "tfe-hvd-eks-tfe"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

# Authenticates to the infra-layer cluster as the HCP TF OIDC run role, which
# the HVD module granted AmazonEKSClusterAdminPolicy via an EKS access entry.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.tfe.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.tfe.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.tfe.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.tfe.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.tfe.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.tfe.token
  }
}
