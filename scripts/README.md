# TFE Secrets Setup

`create_tfe_secrets.sh` is a one-time setup script that generates self-signed TLS material and creates the AWS Secrets Manager secrets required by the TFE HVD modules before a `terraform apply`. It serves both deployments in this repo:

- **EC2** ([`../ec2/`](../ec2/)) uses the license, encryption password, database password, and TLS secrets.
- **EKS** ([`../eks/`](../eks/)) uses the database password and the Redis password. The remaining TFE secrets (license, TLS, encryption password) are supplied to the Helm chart at install time, not to the Terraform module.

Running the script once creates the full superset, so both deployments are covered.

Secrets that already exist are skipped (their existing ARN is printed), so re-running the script is safe. To overwrite existing secrets with newly generated values, pass `--rotate` — the script asks for confirmation first.

> ⚠️ Do not use `--rotate` against a live TFE deployment. It rotates the encryption, database, and Redis passwords in Secrets Manager. The encryption and database passwords are not re-read by a running instance/RDS, so rotating them breaks TFE. The Redis password is only disruptive where it is wired in (EKS always; EC2 only if `tfe_redis_password_secret_arn` is set) and requires a follow-up `terraform apply` to stay in sync.

## Prerequisites

- `aws` CLI, configured with credentials that have Secrets Manager write access
- `openssl`

## Required environment variables

| Variable | Description |
|---|---|
| `TFE_HOSTED_ZONE` | Route 53 hosted zone the wildcard cert covers (e.g. `example.com`). The cert is issued for `*.<zone>` and `<zone>`, so it serves every TFE subdomain (EC2 and EKS) under it |
| `AWS_REGION` | AWS region to create the secrets in |
| `SECRET_PREFIX` | Prefix for secret names (e.g. `tfe-demo`) |
| `TFE_LICENSE_PATH` | Path to your TFE license file (`.hclic`) |

## Usage

```bash
export TFE_HOSTED_ZONE="example.com"
export AWS_REGION="ap-southeast-1"
export SECRET_PREFIX="tfe-demo"
export TFE_LICENSE_PATH="/path/to/terraform.hclic"

./scripts/create_tfe_secrets.sh

# To overwrite existing secrets (e.g. before a fresh deployment):
./scripts/create_tfe_secrets.sh --rotate
```

The ARN for each secret is printed as it is created (or skipped). You do **not** need to copy these ARNs anywhere: both the `ec2/` and `eks/` configs resolve them by name via `data.aws_secretsmanager_secret` from the `secret_prefix` variable (default `tfe-demo`, matching `SECRET_PREFIX` here). Just keep `SECRET_PREFIX` and `secret_prefix` in sync, and ensure the workspace run role has `secretsmanager:DescribeSecret` and `secretsmanager:GetSecretValue` on `<prefix>/*` (see the root README's IAM notes for which layer reads what).

## What gets created

| Secret (`<prefix>/...`) | Format | Contents |
|---|---|---|
| `tfe-license` | Plaintext | Raw `.hclic` file contents |
| `tfe-encryption-password` | Plaintext | Randomly generated 32-char password |
| `tfe-database-password` | Plaintext | Randomly generated 24-char password |
| `tfe-redis-password` | Plaintext | Randomly generated 24-char password (EKS only) |
| `tfe-tls-cert` | Plaintext (base64) | Self-signed TLS certificate (PEM) |
| `tfe-tls-privkey` | Plaintext (base64) | TLS private key (PEM) |
| `tfe-tls-ca-bundle` | Plaintext (base64) | Self-signed CA certificate (PEM) |

TLS secrets are base64-encoded as required by the HVD module. The `tfe-redis-password` secret is **required** by the EKS deployment and **optional** for EC2 — the EC2 HVD module manages the Redis password internally when `tfe_redis_password_secret_arn` is left unset, so it is created here mainly for EKS.