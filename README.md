# tfe-hvd-aws

Terraform configuration for deploying HashiCorp Terraform Enterprise (TFE) on AWS using the [HVD (HashiCorp Validated Design) module](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest).

## Overview

This configuration provisions:

- A dedicated VPC (`172.31.0.0/16`) with public, private, and database subnets across all available AZs
- A TFE instance deployed into private subnets, fronted by a load balancer in public subnets
- An RDS database using dedicated database subnets
- All sensitive values sourced from AWS Secrets Manager

## Prerequisites

- Terraform >= 1.x
- AWS credentials configured with sufficient permissions to create VPC, EC2, RDS, and Secrets Manager resources
- The following secrets pre-created in AWS Secrets Manager:
  - TFE license file
  - TFE encryption password
  - TFE database password
  - TLS certificate, private key, and CA bundle (PEM format)
- A DNS record pointing your chosen FQDN to the load balancer

## Usage

1. Clone this repository.

2. Copy the example vars file and fill in your values:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Initialize and apply:

   ```sh
   terraform init
   terraform plan
   terraform apply
   ```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `friendly_name_prefix` | `string` | `"tfe"` | Prefix applied to all AWS resource names |
| `tfe_fqdn` | `string` | — | FQDN for the TFE instance (e.g. `tfe.example.com`) |
| `tfe_license_secret_arn` | `string` | — | Secrets Manager ARN for the TFE license |
| `tfe_encryption_password_secret_arn` | `string` | — | Secrets Manager ARN for the TFE encryption password |
| `tfe_database_password_secret_arn` | `string` | — | Secrets Manager ARN for the database password |
| `tfe_tls_cert_secret_arn` | `string` | — | Secrets Manager ARN for the TLS certificate |
| `tfe_tls_privkey_secret_arn` | `string` | — | Secrets Manager ARN for the TLS private key |
| `tfe_tls_ca_bundle_secret_arn` | `string` | — | Secrets Manager ARN for the TLS CA bundle |

## Networking Layout

| Subnet type | CIDRs |
|-------------|-------|
| Public (load balancer) | `172.31.101.0/24`, `172.31.102.0/24`, `172.31.103.0/24` |
| Private (EC2) | `172.31.1.0/24`, `172.31.2.0/24`, `172.31.3.0/24` |
| Database (RDS) | `172.31.201.0/24`, `172.31.202.0/24`, `172.31.203.0/24` |

## Module Sources

| Module | Registry |
|--------|----------|
| `tfe_hvd` | [hashicorp/terraform-enterprise-hvd/aws ~> 0.4.0](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest) |
| `tfe_vpc` | [terraform-aws-modules/vpc/aws ~> 6.6.1](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) |
