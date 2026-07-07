terraform {
  required_version = ">= 1.15.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
  cloud {
    organization = "jaz-hashi"
    workspaces {
      name = "tfe-hvd-aws-dev"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
  default_tags {
    tags = merge(var.tags, {
      managed_by = "terraform"
    })
  }
}
