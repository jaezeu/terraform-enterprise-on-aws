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
      name = "tfe-hvd-ocp-tfe"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

# Authenticates as system:admin with the installer-issued client certificate
# (valid 10 years). The three cluster_* variables are sensitive workspace
# variables uploaded by scripts/set-cluster-auth.sh from the installer
# kubeconfig — see this layer's section in openshift/README.md.
provider "kubernetes" {
  host                   = local.cluster.api_url
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  client_certificate     = base64decode(var.cluster_client_certificate)
  client_key             = base64decode(var.cluster_client_key)
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster.api_url
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    client_certificate     = base64decode(var.cluster_client_certificate)
    client_key             = base64decode(var.cluster_client_key)
  }
}
