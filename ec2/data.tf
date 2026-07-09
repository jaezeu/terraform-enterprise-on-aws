data "aws_availability_zones" "available" {
  state = "available"
}

# Resolve secret ARNs by name (created by scripts/create_tfe_secrets.sh) —
# no hardcoded ARNs. Metadata only: values are read at instance boot via the
# instance profile, so the run role needs just secretsmanager:DescribeSecret.
locals {
  tfe_secret_names = {
    license             = "tfe-license"
    encryption_password = "tfe-encryption-password"
    database_password   = "tfe-database-password"
    redis_password      = "tfe-redis-password"
    tls_cert            = "tfe-tls-cert"
    tls_privkey         = "tfe-tls-privkey"
    tls_ca_bundle       = "tfe-tls-ca-bundle"
  }
}

data "aws_secretsmanager_secret" "tfe" {
  for_each = local.tfe_secret_names
  name     = "${var.secret_prefix}/${each.value}"
}
