# Outputs of the cluster layer. Requires remote state sharing to be enabled on
# the tfe-hvd-ocp-cluster workspace for this workspace.
data "terraform_remote_state" "cluster" {
  backend = "remote"

  config = {
    organization = "jaz-hashi"
    workspaces = {
      name = "tfe-hvd-ocp-cluster"
    }
  }
}

# try(): if the cluster workspace was already destroyed its outputs are gone,
# but this layer must still be able to plan its own destroy (deletes use
# values recorded in state, not these expressions).
locals {
  cluster_outputs = data.terraform_remote_state.cluster.outputs
  cluster = {
    api_url             = try(local.cluster_outputs.api_url, "https://cluster-gone.invalid")
    infra_id            = try(local.cluster_outputs.infra_id, "unused")
    base_domain         = try(local.cluster_outputs.base_domain, "unused")
    base_domain_zone_id = try(local.cluster_outputs.base_domain_zone_id, "unused")
    vpc_id              = try(local.cluster_outputs.vpc_id, "unused")
    vpc_cidr            = try(local.cluster_outputs.vpc_cidr, "10.10.0.0/16")
    private_subnet_ids  = try(local.cluster_outputs.private_subnet_ids, [])
    worker_role_name    = try(local.cluster_outputs.worker_role_name, "unused")
  }
}

data "aws_region" "current" {}

# Secret VALUES consumed by the deployment — the same Secrets Manager entries
# the ec2/ and eks/ stacks use (created by scripts/create_tfe_secrets.sh).
# The run role needs secretsmanager:GetSecretValue on <secret_prefix>/*.
locals {
  tfe_secret_value_names = {
    license             = "tfe-license"
    encryption_password = "tfe-encryption-password"
    database_password   = "tfe-database-password"
    redis_password      = "tfe-redis-password"
    tls_cert            = "tfe-tls-cert"
    tls_privkey         = "tfe-tls-privkey"
    tls_ca_bundle       = "tfe-tls-ca-bundle"
  }
}

data "aws_secretsmanager_secret_version" "tfe" {
  for_each  = local.tfe_secret_value_names
  secret_id = "${var.secret_prefix}/${each.value}"
}
