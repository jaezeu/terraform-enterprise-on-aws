# tfe-hvd-aws

Terraform configurations for deploying HashiCorp Terraform Enterprise (TFE) on AWS using the [HashiCorp Validated Design (HVD)](https://developer.hashicorp.com/validated-designs) modules. This repo hosts two independent deployments of the same product, side by side, in the same AWS account — used for learning and demos.

| Deployment | Directory | Module | HCP TF Workspace(s) |
|---|---|---|---|
| TFE on **EC2** | [`ec2/`](ec2/) | [terraform-enterprise-hvd/aws](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-hvd/aws/latest) | `tfe-hvd-aws-dev` |
| TFE on **EKS** | [`eks/`](eks/) | [terraform-enterprise-eks-hvd/aws](https://registry.terraform.io/modules/hashicorp/terraform-enterprise-eks-hvd/aws/latest) | `tfe-hvd-eks-infra` → `-addons` → `-tfe` |

Every directory is a self-contained, CLI-driven root module with its own HCP Terraform workspace (all in the `jaz-hashi` org, Default Project) and its own state. See the per-deployment READMEs:

- **[ec2/README.md](ec2/README.md)** — TFE on EC2 with RDS + ElastiCache; single apply.
- **[eks/README.md](eks/README.md)** — TFE on EKS in three layered workspaces (infra → addons → tfe), DNS via external-dns.

---

## Repository layout

```
.
├── ec2/           # TFE on EC2 → workspace tfe-hvd-aws-dev (single apply)
├── eks/           # TFE on EKS — three layered workspaces, applied in order:
│   ├── infra/     #   1. tfe-hvd-eks-infra  (VPC, EKS, Aurora, Redis, S3, IRSA)
│   ├── addons/    #   2. tfe-hvd-eks-addons (AWS LB Controller, external-dns)
│   └── tfe/       #   3. tfe-hvd-eks-tfe    (k8s secrets, TFE Helm chart)
└── scripts/       # shared: create_tfe_secrets.sh (Secrets Manager bootstrap)
```

The two deployments use distinct `friendly_name_prefix` / `tfe_fqdn` values so they can coexist in the same account. Each creates its own VPC (both currently `172.31.0.0/16` — separate VPCs, so no conflict, but they can never be peered while the CIDRs match).

---

## Shared prerequisites

Both deployments depend on three things created outside this repo's root modules:

1. **Dynamic-credentials IAM role.** Each workspace authenticates to AWS via HCP Terraform [dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials) (OIDC) — no static AWS keys are stored in HCP TF. The `aws_iam_openid_connect_provider` and the assumed IAM role are managed in a **separate bootstrap repo** run with local AWS credentials. All workspaces are wired to the same role via the `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` env variables. Besides broad infrastructure permissions, the role needs on `arn:aws:secretsmanager:<region>:<account>:secret:<secret_prefix>/*`:
   - `secretsmanager:DescribeSecret` — both deployments resolve secret ARNs by name
   - `secretsmanager:GetSecretValue` — the modules read the DB/Redis passwords to create RDS/ElastiCache, and the EKS `tfe` layer reads the license/TLS/encryption values to build Kubernetes secrets

2. **Secrets in AWS Secrets Manager.** Run [`scripts/create_tfe_secrets.sh`](scripts/) once — it creates all seven TFE secrets (license, encryption/DB/Redis passwords, wildcard TLS cert + key + CA) under one `SECRET_PREFIX`. **Both deployments share the same secrets**; no ARNs are ever copied into workspace variables. See [scripts/README.md](scripts/README.md).

3. **A public Route 53 hosted zone** for the TFE hostnames (one zone serves both deployments; the TLS cert is a wildcard on it).

---

## Getting started

```sh
# 0. Authenticate
terraform login          # HCP Terraform, first time only
# (AWS CLI creds are only needed for the secrets script — Terraform runs use OIDC)

# 1. Create the Secrets Manager secrets (once)
export TFE_HOSTED_ZONE="example.com"
export AWS_REGION="ap-southeast-1"
export SECRET_PREFIX="tfe-demo"
export TFE_LICENSE_PATH="/path/to/terraform.hclic"
./scripts/create_tfe_secrets.sh

# 2a. TFE on EC2 — single apply
cd ec2 && terraform init && terraform apply

# 2b. TFE on EKS — three applies, in order (see eks/README.md for the
#     one-time remote-state-sharing setting first)
cd eks/infra  && terraform init && terraform apply
cd ../addons  && terraform init && terraform apply
cd ../tfe     && terraform init && terraform apply
```

Teardown is the reverse: `eks/tfe` → `eks/addons` → `eks/infra`, and/or `ec2`.

### Workspace variables

| Workspace | Terraform variables | Env variables |
|---|---|---|
| `tfe-hvd-aws-dev` | `friendly_name_prefix`, `tfe_fqdn`, `route53_tfe_hosted_zone_name` | `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN` |
| `tfe-hvd-eks-infra` | `friendly_name_prefix`, `tfe_fqdn`, `route53_tfe_hosted_zone_name` | `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN` |
| `tfe-hvd-eks-addons` | — (reads infra remote state) | `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN` |
| `tfe-hvd-eks-tfe` | — (reads infra remote state; `secret_prefix`/`tfe_image_tag` optional) | `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN` |

Secret ARNs are never workspace variables — configs resolve them by name from `secret_prefix` (default `tfe-demo`).

---

## Adapting this repo

To use this repo in your own org/account, change:

1. **`cloud {}` blocks** in `ec2/provider.tf`, `eks/infra/provider.tf`, `eks/addons/provider.tf`, `eks/tfe/provider.tf` — your HCP TF organization and workspace names. Also update the two `terraform_remote_state` blocks (`eks/addons/data.tf`, `eks/tfe/data.tf`) if you rename the infra workspace.
2. **Region** — hardcoded as `ap-southeast-1` in each `provider.tf`.
3. **Workspaces** — create the four workspaces, set the variables per the table above, and enable **remote state sharing** on the EKS infra workspace for the addons + tfe workspaces.
4. **OIDC role** — point `TFC_AWS_RUN_ROLE_ARN` at your own dynamic-credentials role (trust policy scoped to your org/workspaces).
5. **Domain values** — your hosted zone and two distinct FQDNs (one per deployment).
6. **TFE license** — your own `.hclic` for the secrets script.

Costs to expect while running: ~3 NAT gateways + NLB + RDS + ElastiCache per deployment, plus an EKS control plane and 3 nodes on the EKS side — destroy when not demoing.
