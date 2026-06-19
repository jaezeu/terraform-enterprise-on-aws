# Terraform Enterprise on AWS EC2

Terraform configuration for deploying HashiCorp Terraform Enterprise (TFE) on AWS using the [HVD (HashiCorp Validated Design) module](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest).

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
| Secrets | AWS Secrets Manager |
| State backend | HCP Terraform (`tfe-hvd-aws-dev`) |

---

## Prerequisites

- Terraform >= 1.15.6
- HCP Terraform account with access to the `jaz-hashi` organization and `tfe-hvd-aws-dev` workspace
- AWS credentials with sufficient permissions (VPC, EC2, RDS, ElastiCache, NLB, Route 53, Secrets Manager)
- The following secrets pre-created in AWS Secrets Manager:
  - TFE license file
  - TFE encryption password
  - TFE database password
  - TLS certificate, private key, and CA bundle (PEM format)
- A Route 53 hosted zone for the target domain

---

## Usage

1. Clone this repository.

2. Authenticate to HCP Terraform:

   ```sh
   terraform login
   ```

3. Provide values for all required variables (see [Variables](#variables) below), then initialize and apply:

   ```sh
   terraform init
   terraform plan
   terraform apply
   ```

---

## Variables

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `friendly_name_prefix` | `string` | yes | Prefix applied to all AWS resource names for uniqueness |
| `tfe_fqdn` | `string` | yes | FQDN for the TFE instance (e.g. `tfe.example.com`) |
| `route53_tfe_hosted_zone_name` | `string` | yes | Route 53 hosted zone name (e.g. `example.com`) |
| `tfe_license_secret_arn` | `string` | yes | Secrets Manager ARN for the TFE license |
| `tfe_encryption_password_secret_arn` | `string` | yes | Secrets Manager ARN for the TFE encryption password |
| `tfe_database_password_secret_arn` | `string` | yes | Secrets Manager ARN for the database password |
| `tfe_tls_cert_secret_arn` | `string` | yes | Secrets Manager ARN for the TLS certificate |
| `tfe_tls_privkey_secret_arn` | `string` | yes | Secrets Manager ARN for the TLS private key |
| `tfe_tls_ca_bundle_secret_arn` | `string` | yes | Secrets Manager ARN for the TLS CA bundle |
| `tags` | `map(string)` | no | Additional tags applied to all AWS resources |

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

## Networking Layout

| Tier | Resources |
|------|-----------|
| Public | NLB, NAT Gateways |
| Private | EC2 (TFE application) |
| Database | RDS, Redis |

---

## Module Sources

| Module | Source | Version |
|--------|--------|---------|
| `tfe_hvd` | [hashicorp/terraform-enterprise-hvd/aws](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest) | `~> 0.4.0` |
| `tfe_vpc` | [terraform-aws-modules/vpc/aws](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) | `~> 5.0` |
