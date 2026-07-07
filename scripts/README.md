# TFE Secrets Setup

`create_tfe_secrets.sh` is a one-time setup script that generates self-signed TLS material and creates the six AWS Secrets Manager secrets required by the [terraform-aws-terraform-enterprise-hvd](https://github.com/hashicorp/terraform-aws-terraform-enterprise-hvd) module before a `terraform apply`.

Secrets that already exist are skipped (their existing ARN is printed), so re-running the script is safe. To overwrite existing secrets with newly generated values, pass `--rotate` — the script asks for confirmation first.

> ⚠️ Do not use `--rotate` against a live TFE deployment. It rotates the encryption and database passwords in Secrets Manager without updating the running instance or RDS, which will break TFE.

## Prerequisites

- `aws` CLI, configured with credentials that have Secrets Manager write access
- `openssl`

## Required environment variables

| Variable | Description |
|---|---|
| `TFE_DOMAIN` | FQDN for the TFE instance (e.g. `tfe.example.com`) |
| `AWS_REGION` | AWS region to create the secrets in |
| `SECRET_PREFIX` | Prefix for secret names (e.g. `tfe-demo`) |
| `TFE_LICENSE_PATH` | Path to your TFE license file (`.hclic`) |

## Usage

```bash
export TFE_DOMAIN="tfe-demo.example.com"
export AWS_REGION="ap-southeast-1"
export SECRET_PREFIX="tfe-demo"
export TFE_LICENSE_PATH="/path/to/terraform.hclic"

./scripts/create_tfe_secrets.sh

# To overwrite existing secrets (e.g. before a fresh deployment):
./scripts/create_tfe_secrets.sh --rotate
```

The ARN for each secret is printed as it is created (or skipped). Use these values to populate the following variables in your `terraform.tfvars`:

```hcl
tfe_license_secret_arn             = "..."
tfe_encryption_password_secret_arn = "..."
tfe_database_password_secret_arn   = "..."
tfe_tls_cert_secret_arn            = "..."
tfe_tls_privkey_secret_arn         = "..."
tfe_tls_ca_bundle_secret_arn       = "..."
```

## What gets created

| Secret (`<prefix>/...`) | Format | Contents |
|---|---|---|
| `tfe-license` | Plaintext | Raw `.hclic` file contents |
| `tfe-encryption-password` | Plaintext | Randomly generated 32-char password |
| `tfe-database-password` | Plaintext | Randomly generated 24-char password |
| `tfe-tls-cert` | Plaintext (base64) | Self-signed TLS certificate (PEM) |
| `tfe-tls-privkey` | Plaintext (base64) | TLS private key (PEM) |
| `tfe-tls-ca-bundle` | Plaintext (base64) | Self-signed CA certificate (PEM) |

TLS secrets are base64-encoded as required by the HVD module.