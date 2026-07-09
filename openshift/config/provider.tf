terraform {
  required_version = ">= 1.15.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  cloud {
    organization = "jaz-hashi"
    workspaces {
      name = "tfe-hvd-ocp-config"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}
