# Terraform Enterprise on AWS EC2

Deploys HashiCorp Terraform Enterprise (TFE) on AWS EC2 using the [terraform-enterprise-hvd/aws](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest) HVD module.

State is managed remotely via HCP Terraform (`jaz-hashi` org, workspace `tfe-hvd-aws-dev`).

---

## Overview

| Component | Detail |
|-----------|--------|
| Region | `ap-southeast-1` |
| Availability Zones | All available AZs (dynamic) |
| Load Balancer | Internet-facing NLB in public subnets |
| TFE Application | EC2 instances in private subnets |
| Database | RDS (PostgreSQL) in database subnets |
| Cache | Redis (ElastiCache) in database subnets |
| NAT Gateways | One per AZ (high-availability) |
| DNS | Route 53 public hosted zone |
| VPC CIDR | `172.31.0.0/16` |
| Secrets | AWS Secrets Manager |
| State backend | HCP Terraform (`tfe-hvd-aws-dev`) |

---

## Prerequisites

- Terraform >= 1.15.6
- HCP Terraform access to the `jaz-hashi` organization and `tfe-hvd-aws-dev` workspace
- The dynamic-credentials IAM role that the workspace assumes via OIDC (managed in a separate bootstrap repo — see the [root README](../README.md))
- Secrets pre-created in AWS Secrets Manager via [`../scripts/create_tfe_secrets.sh`](../scripts/): license, encryption password, database password, and TLS certificate / private key / CA bundle
- A Route 53 hosted zone for the target domain

---

## Usage

Run all commands from this `ec2/` directory.

```sh
terraform login   # first time only
terraform init
terraform plan
terraform apply
```

The workspace is CLI-driven: the `cloud {}` block in [provider.tf](provider.tf) points runs at `tfe-hvd-aws-dev`, and authentication to AWS uses HCP TF dynamic credentials (no static keys).

---

## First-time setup: initial admin user

After the apply completes and TFE is healthy, create the first admin user with the Initial Admin Creation Token (IACT). This config does **not** set `tfe_iact_subnets`, so the `/admin/retrieve-iact` network endpoint is disabled — retrieve the token directly on the instance over SSM instead (`ec2_allow_ssm = true` is set for this).

1. Find the running TFE instance (`friendly_name_prefix` is the tag prefix):

   ```sh
   aws ec2 describe-instances --region ap-southeast-1 \
     --filters "Name=tag:Name,Values=<friendly_name_prefix>*" "Name=instance-state-name,Values=running" \
     --query 'Reservations[].Instances[].InstanceId' --output text
   ```

2. Start an SSM session (requires the `session-manager-plugin` locally):

   ```sh
   aws ssm start-session --region ap-southeast-1 --target <instance-id>
   ```

3. On the instance, find the TFE container and retrieve the token:

   ```sh
   sudo docker ps --format '{{.Names}}'                 # confirm the TFE container name
   sudo docker exec <container-name> tfectl admin token
   ```

4. Create the admin user by opening (in a browser):

   ```
   https://<tfe_fqdn>/admin/account/new?token=<TOKEN>
   ```

Notes:
- The IACT is valid only until the first admin user is created, and retrieval is time-bounded by `tfe_iact_time_limit` (default 60 min after startup). Re-run `tfectl admin token` on the node to reissue while no admin exists yet.
- Alternatively, set `tfe_iact_subnets` to your public IP (`"x.x.x.x/32"`) and re-apply to enable browser retrieval via `https://<tfe_fqdn>/admin/retrieve-iact`.
- See the [initial admin user docs](https://developer.hashicorp.com/terraform/enterprise/deploy/initial-admin-user) for the API method and other runtimes.

---

## Variables

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `friendly_name_prefix` | `string` | yes | Prefix applied to all AWS resource names for uniqueness |
| `tfe_fqdn` | `string` | yes | FQDN for the TFE instance (e.g. `tfe.example.com`) |
| `route53_tfe_hosted_zone_name` | `string` | yes | Route 53 hosted zone name (e.g. `example.com`) |
| `secret_prefix` | `string` | no | Prefix for the TFE secret names in Secrets Manager (default `tfe-demo`). All secret ARNs are resolved by name via data sources — no per-secret ARN variables are set |
| `tags` | `map(string)` | no | Additional tags applied to all AWS resources |

The TFE secrets (license, encryption password, database password, Redis password, TLS cert/key/CA bundle) are looked up by name under `secret_prefix` in [data.tf](data.tf), so you never set their ARNs as variables. The workspace's run role needs `secretsmanager:DescribeSecret` on `<prefix>/*` (ARN resolution) and `secretsmanager:GetSecretValue` on the DB/Redis password secrets (the HVD module reads those values to create RDS/ElastiCache); the remaining secret values are read at instance boot via the instance profile, not by Terraform.

---

## Outputs

| Name | Description |
|------|-------------|
| `tfe_url` | HTTPS URL of the TFE instance |
| `vpc_id` | ID of the VPC |
| `public_subnet_ids` | Subnet IDs for the load balancer tier |
| `private_subnet_ids` | Subnet IDs for the EC2/TFE tier |
| `database_subnet_ids` | Subnet IDs for the RDS/Redis tier |

---

## Module Sources

| Module | Source | Version |
|--------|--------|---------|
| `tfe_hvd` | [hashicorp/terraform-enterprise-hvd/aws](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest) | `~> 0.4.0` |
| `tfe_vpc` | [terraform-aws-modules/vpc/aws](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) | `~> 5.0` |
