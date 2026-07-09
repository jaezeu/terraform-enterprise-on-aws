# =============================================================================
# Layer 1: infrastructure — VPC, EKS cluster, Aurora, Redis, S3, IRSA roles.
# Applied first. The addons and tfe layers read this workspace's outputs via
# terraform_remote_state (enable remote state sharing on this workspace).
# =============================================================================

module "tfe_eks" {
  # The latest published release (0.1.2) still constrains the AWS provider to
  # ~> 5.63 (< 6.0). AWS provider 6.x support currently exists only on the
  # module's main branch, so we source it from a pinned commit until a 6.x-
  # compatible version is released.
  source = "git::https://github.com/hashicorp/terraform-aws-terraform-enterprise-eks-hvd.git?ref=a7af6f81ef2f0207f8883caa6e6fa83536b468f5"

  # Naming
  friendly_name_prefix = var.friendly_name_prefix
  common_tags          = var.tags

  # DNS
  tfe_fqdn = var.tfe_fqdn

  # Networking
  vpc_id           = module.tfe_vpc.vpc_id
  eks_subnet_ids   = module.tfe_vpc.private_subnets
  rds_subnet_ids   = module.tfe_vpc.database_subnets
  redis_subnet_ids = module.tfe_vpc.database_subnets

  # Create a new EKS cluster and the IRSA for it
  create_eks_cluster            = true
  create_eks_oidc_provider      = true
  create_tfe_eks_irsa           = true
  create_aws_lb_controller_irsa = true

  # Internet-facing access (demo). Lock these CIDRs down for production.
  eks_cluster_endpoint_public_access = true
  eks_cluster_public_access_cidrs    = ["0.0.0.0/0"]
  cidr_allow_ingress_tfe_443         = ["0.0.0.0/0"]

  # Secrets — resolved by name from var.secret_prefix (see data.tf)
  tfe_database_password_secret_arn = data.aws_secretsmanager_secret.tfe["database_password"].arn
  tfe_redis_password_secret_arn    = data.aws_secretsmanager_secret.tfe["redis_password"].arn

  # The tfe layer builds chart values from this workspace's outputs instead
  create_helm_overrides_file = false

  # Demo teardown settings — keep both false in production (protects state data)
  rds_skip_final_snapshot = true
  force_destroy_s3_bucket = true
}

module "tfe_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name             = "tfe-eks-vpc"
  cidr             = "172.31.0.0/16"
  azs              = data.aws_availability_zones.available.names
  public_subnets   = ["172.31.101.0/24", "172.31.102.0/24", "172.31.103.0/24"]
  private_subnets  = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
  database_subnets = ["172.31.201.0/24", "172.31.202.0/24", "172.31.203.0/24"]

  create_database_subnet_route_table = true
  enable_nat_gateway                 = true
  single_nat_gateway                 = false
  map_public_ip_on_launch            = true

  # Tags required for the AWS Load Balancer Controller to auto-discover subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IRSA role for external-dns (the HVD module creates IRSA roles for TFE and the
# AWS LB Controller, but not for external-dns). Trust is bound to the
# external-dns service account installed by the addons layer.
# -----------------------------------------------------------------------------
locals {
  eks_oidc_issuer_host     = trimprefix(data.aws_eks_cluster.tfe.identity[0].oidc[0].issuer, "https://")
  external_dns_namespace   = "external-dns"
  external_dns_svc_account = "external-dns"
}

resource "aws_iam_role" "external_dns_irsa" {
  name = "${var.friendly_name_prefix}-external-dns-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.eks_oidc_issuer_host}:sub" = "system:serviceaccount:${local.external_dns_namespace}:${local.external_dns_svc_account}"
          "${local.eks_oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "external_dns" {
  name = "${var.friendly_name_prefix}-external-dns-route53"
  role = aws_iam_role.external_dns_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = [data.aws_route53_zone.tfe.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = ["*"]
      }
    ]
  })
}
