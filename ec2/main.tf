module "tfe_hvd" {
  source  = "hashicorp/terraform-enterprise-hvd/aws"
  version = "~> 0.4.0"

  # Naming
  friendly_name_prefix = var.friendly_name_prefix

  # Networking
  lb_type          = "nlb"
  lb_is_internal   = false
  vpc_id           = module.tfe_vpc.vpc_id
  ec2_subnet_ids   = module.tfe_vpc.private_subnets
  lb_subnet_ids    = module.tfe_vpc.public_subnets
  rds_subnet_ids   = module.tfe_vpc.database_subnets
  redis_subnet_ids = module.tfe_vpc.database_subnets

  # DNS
  create_route53_tfe_dns_record      = true
  route53_tfe_hosted_zone_is_private = false
  tfe_fqdn                           = var.tfe_fqdn
  route53_tfe_hosted_zone_name       = var.route53_tfe_hosted_zone_name

  # Secrets Manager ARNs — resolved by name from var.secret_prefix (see data.tf)
  tfe_license_secret_arn             = data.aws_secretsmanager_secret.tfe["license"].arn
  tfe_encryption_password_secret_arn = data.aws_secretsmanager_secret.tfe["encryption_password"].arn
  tfe_database_password_secret_arn   = data.aws_secretsmanager_secret.tfe["database_password"].arn
  tfe_redis_password_secret_arn      = data.aws_secretsmanager_secret.tfe["redis_password"].arn
  tfe_tls_cert_secret_arn            = data.aws_secretsmanager_secret.tfe["tls_cert"].arn
  tfe_tls_privkey_secret_arn         = data.aws_secretsmanager_secret.tfe["tls_privkey"].arn
  tfe_tls_ca_bundle_secret_arn       = data.aws_secretsmanager_secret.tfe["tls_ca_bundle"].arn

  # EC2
  ec2_allow_ssm = true

  # Demo teardown settings — keep both false in production (protects state data)
  rds_skip_final_snapshot = true
  s3_force_destroy        = true
}

module "tfe_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                               = "tfe-vpc"
  cidr                               = "172.31.0.0/16"
  azs                                = data.aws_availability_zones.available.names
  public_subnets                     = ["172.31.101.0/24", "172.31.102.0/24", "172.31.103.0/24"]
  private_subnets                    = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
  database_subnets                   = ["172.31.201.0/24", "172.31.202.0/24", "172.31.203.0/24"]
  create_database_subnet_route_table = true
  enable_nat_gateway                 = true
  single_nat_gateway                 = false
  map_public_ip_on_launch            = true

  tags = var.tags
}
