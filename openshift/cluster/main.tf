# OpenShift 4 UPI on AWS — Terraform translation of the official UPI
# CloudFormation templates. Inputs come from scripts/bootstrap.sh
# (cluster.auto.tfvars.json); full flow in ../README.md.

locals {
  cluster_domain = "${var.cluster_name}.${var.base_domain}"
  # Every resource the cluster's cloud provider must discover carries this tag.
  cluster_tag = { "kubernetes.io/cluster/${var.infra_id}" = "shared" }

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "${var.infra_id}-vpc"
  cidr            = var.vpc_cidr
  azs             = local.azs
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true # demo cost saving; one per AZ for production
  enable_dns_support = true

  enable_dns_hostnames = true

  public_subnet_tags = merge(local.cluster_tag, {
    "kubernetes.io/role/elb" = "1"
  })
  private_subnet_tags = merge(local.cluster_tag, {
    "kubernetes.io/role/internal-elb" = "1"
  })

  tags = var.tags
}
