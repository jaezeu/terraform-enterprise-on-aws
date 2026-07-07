data "aws_availability_zones" "available" {
  state = "available"
}

# Resolve the TFE secret ARNs by name from the shared `secret_prefix`, so the
# workspace never has to hold hardcoded ARNs. Names match those created by
# scripts/create_tfe_secrets.sh. Only metadata is read here (the ARN) — the
# secret values are read at instance boot via the EC2 instance profile — so the
# run role needs only secretsmanager:DescribeSecret on these.
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
