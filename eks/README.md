# Terraform Enterprise on AWS EKS

Deploys HashiCorp Terraform Enterprise (TFE) on EKS in **three layered HCP Terraform workspaces**, applied in order. Layering keeps the cluster and its in-cluster resources in separate states (avoiding the Terraform "stacking" anti-pattern), keeps each apply short (no EKS auth-token expiry risk), and lets app changes plan in seconds without touching infrastructure.

| Layer | Directory | Workspace | Contents |
|---|---|---|---|
| 1. Infra | [`infra/`](infra/) | `tfe-hvd-eks-infra` | VPC, [HVD module](https://github.com/hashicorp/terraform-aws-terraform-enterprise-eks-hvd) (EKS, Aurora, Redis, S3, IRSA), external-dns IRSA role |
| 2. Addons | [`addons/`](addons/) | `tfe-hvd-eks-addons` | AWS Load Balancer Controller, external-dns |
| 3. TFE | [`tfe/`](tfe/) | `tfe-hvd-eks-tfe` | Namespace, Kubernetes secrets (from Secrets Manager), TFE Helm chart |

Downstream layers read the infra workspace's outputs via `terraform_remote_state` — cluster name, IRSA ARNs, endpoints, and even `tfe_fqdn` flow from one source of truth. **DNS:** the TFE Service carries an `external-dns.alpha.kubernetes.io/hostname` annotation; external-dns watches it and creates/repairs the Route 53 record as soon as the AWS LB Controller provisions the NLB. No Terraform DNS resource — the record self-heals if the NLB is ever recreated.

---

## One-time setup

1. **Secrets** — run [`../scripts/create_tfe_secrets.sh`](../scripts/) once (creates all 7 secrets, wildcard TLS cert).
2. **IAM** — the OIDC run role needs `secretsmanager:GetSecretValue` + `DescribeSecret` on `<secret_prefix>/*` (the tfe layer injects secret values into Kubernetes secrets).
3. **Remote state sharing** — on workspace `tfe-hvd-eks-infra` → Settings → General → Remote state sharing: share with `tfe-hvd-eks-addons` and `tfe-hvd-eks-tfe`. (Not settable via API tooling used here.)
4. Workspace variables are already configured: infra holds `friendly_name_prefix`, `tfe_fqdn`, `route53_tfe_hosted_zone_name` + OIDC env vars; addons/tfe hold only OIDC env vars.

---

## Deploy

Apply the layers in order (each directory is CLI-driven against its workspace):

```sh
cd infra  && terraform init && terraform apply   # ~40-50 min (EKS, Aurora, Redis)
cd ../addons && terraform init && terraform apply   # ~3-5 min
cd ../tfe    && terraform init && terraform apply   # ~10-20 min (image pull, DB migrations, NLB)
```

A few minutes after the tfe layer finishes, external-dns will have created the Route 53 record and `https://<tfe_fqdn>` is live. Destroy in reverse order (`tfe` → `addons` → `infra`).

> **Optional next step:** connect the workspaces to VCS (working directory per layer + trigger patterns) and add **run triggers** (infra → addons → tfe) so a push cascades through all three automatically.

### First-time setup: initial admin user

TFE is bootstrapped with the Initial Admin Creation Token (IACT), retrieved from the TFE pod with `tfectl`.

**0. Grant yourself cluster access (once).** The HVD module grants EKS cluster admin *only* to the HCP TF OIDC run role that created the cluster (`bootstrap_cluster_creator_admin_permissions = false`), so your own IAM identity gets `Unauthorized` from `kubectl` until you add an [access entry](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html):

```sh
aws sts get-caller-identity   # your principal ARN (for an assumed role, use the underlying arn:aws:iam::…:role/… form)

aws eks create-access-entry \
  --cluster-name <friendly_name_prefix>-tfe-eks-cluster --region ap-southeast-1 \
  --principal-arn <YOUR_PRINCIPAL_ARN>

aws eks associate-access-policy \
  --cluster-name <friendly_name_prefix>-tfe-eks-cluster --region ap-southeast-1 \
  --principal-arn <YOUR_PRINCIPAL_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

**1. Retrieve the IACT token from the pod:**

```sh
aws eks update-kubeconfig --name <friendly_name_prefix>-tfe-eks-cluster --region ap-southeast-1
kubectl exec -it -n tfe deploy/terraform-enterprise -- tfectl admin token
```

**2. Create the admin user** by opening:

```
https://<tfe_fqdn>/admin/account/new?token=<TOKEN>
```

Notes:
- The IACT is retrievable for **60 minutes after the app starts** (TFE default `TFE_IACT_TIME_LIMIT`; no `TFE_IACT_*` env vars are set in this config) and stops working permanently once the first admin user exists.
- Missed the window? Restart the pod to reset it — safe, since all TFE data lives in Aurora/S3/Redis (external services mode):

  ```sh
  kubectl rollout restart deploy/terraform-enterprise -n tfe
  kubectl rollout status  deploy/terraform-enterprise -n tfe   # ~2-5 min
  kubectl exec -it -n tfe deploy/terraform-enterprise -- tfectl admin token
  ```
- The browser retrieval endpoint (`/admin/retrieve-iact`) is disabled because `TFE_IACT_SUBNETS` is unset — same posture as the EC2 deployment. Set it (plus `TFE_IACT_TIME_LIMIT`) under `env.variables` in [tfe/main.tf](tfe/main.tf) if you want that path.

---

## Variables (per workspace)

| Workspace | Variable | Required | Notes |
|---|---|---|---|
| infra | `friendly_name_prefix` | yes | must differ from the EC2 deployment |
| infra | `tfe_fqdn` | yes | downstream layers read it from remote state |
| infra | `route53_tfe_hosted_zone_name` | yes | zone external-dns manages; IRSA policy scoped to it |
| infra | `secret_prefix` | no | default `tfe-demo` |
| tfe | `secret_prefix`, `tfe_image_tag` | no | defaults `tfe-demo` / `v202505-1` |
| addons | — | — | everything comes from remote state |

All three workspaces carry the `TFC_AWS_PROVIDER_AUTH` / `TFC_AWS_RUN_ROLE_ARN` env vars (OIDC dynamic credentials).

Because the tfe layer reads secret values, they are stored in that workspace's **state**; acceptable for a demo — use a secrets operator (e.g. External Secrets) if that's ever not OK.

---

## Sources

| Component | Source | Version |
|---|---|---|
| `tfe_eks` module | [hashicorp/terraform-enterprise-eks-hvd/aws](https://github.com/hashicorp/terraform-aws-terraform-enterprise-eks-hvd) | `main` @ pinned commit `a7af6f8` (AWS provider 6.x support not yet in a registry release — swap back to the registry once released) |
| `tfe_vpc` module | [terraform-aws-modules/vpc/aws](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) | `~> 5.0` |
| TFE Helm chart | [hashicorp/terraform-enterprise-helm](https://github.com/hashicorp/terraform-enterprise-helm) | latest (unpinned) |
| AWS LB Controller chart | [aws/eks-charts](https://github.com/aws/eks-charts) | latest (unpinned) |
| external-dns chart | [kubernetes-sigs/external-dns](https://github.com/kubernetes-sigs/external-dns) | latest (unpinned) |

VPC CIDR is `172.31.0.0/16` — same value as the EC2 deployment (separate VPCs, no conflict, but they can never be peered).
