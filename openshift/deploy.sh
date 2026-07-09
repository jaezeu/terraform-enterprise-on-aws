#!/usr/bin/env bash
# =============================================================================
# deploy.sh — the whole OpenShift + TFE stack, one command, ~90 minutes.
#
#   cluster (bootstrap.sh, terraform, bootstrap teardown, post-install.sh —
#   which also applies config/ *.apps DNS mid-install)
#   -> tfe (RDS/Redis/S3, imds-proxy, Helm)
#
# One-time prereqs before the first run:
#   - aws login (fresh sandbox session), docker running, terraform login
#   - scripts/create_tfe_secrets.sh has been run (license, passwords, TLS)
#   - env vars: OCP_BASE_DOMAIN OCP_CLUSTER_NAME AWS_REGION PULL_SECRET_PATH
#
# Each stage is idempotent-ish for a FRESH build; to re-run after a partial
# failure, comment out the completed stages — they're plain commands, no magic.
# =============================================================================

set -euo pipefail

log() { echo; echo "===== [deploy] $* ====="; }
die() { echo "[ERROR] $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
OC="$ROOT/.bin/oc"
export KUBECONFIG="$ROOT/install-dir/auth/kubeconfig"

log "0/5 preflight — fail here, not 40 minutes in"
for v in OCP_BASE_DOMAIN OCP_CLUSTER_NAME AWS_REGION PULL_SECRET_PATH; do
  [[ -n "${!v:-}" ]] || die "$v is not set (see 'One-time prereqs' in the header)."
done
[[ -f "$PULL_SECRET_PATH" ]] || die "pull secret not found at $PULL_SECRET_PATH (console.redhat.com/openshift/install/pull-secret)."
for cmd in terraform aws jq curl; do
  command -v "$cmd" >/dev/null || die "$cmd is not installed."
done
aws sts get-caller-identity >/dev/null 2>&1 || die "no AWS session — run: aws login"
[[ -f ~/.terraform.d/credentials.tfrc.json ]] || die "no HCP Terraform token — run: terraform login"
if [[ "$(uname -s)" == "Darwin" ]]; then
  docker info >/dev/null 2>&1 || die "docker daemon not running (ccoctl needs it on macOS) — run: colima start"
fi
aws secretsmanager describe-secret --secret-id tfe-demo/tfe-license >/dev/null 2>&1 \
  || die "TFE secrets missing in Secrets Manager — run: scripts/create_tfe_secrets.sh"

log "1/5 cluster: bootstrap (ignition, IAM artifacts, tfvars)"
"$ROOT/scripts/bootstrap.sh"

log "2/5 cluster: provision AWS infra"
terraform -chdir="$ROOT/cluster" init -input=false
terraform -chdir="$ROOT/cluster" apply -auto-approve -input=false

log "3/5 cluster: wait for bootstrap handoff, then remove the bootstrap node"
"$ROOT/.bin/openshift-install" wait-for bootstrap-complete --dir "$ROOT/install-dir"
terraform -chdir="$ROOT/cluster" apply -auto-approve -input=false -var bootstrap_enabled=false

log "4/5 cluster: CSRs + registry + *.apps DNS + install-complete"
"$ROOT/scripts/post-install.sh"

log "cleanup: ignition bucket (secrets, no longer needed)"
aws s3 rb "s3://$(jq -r .bootstrap_ign_bucket "$ROOT/cluster/cluster.auto.tfvars.json")" --force

log "5/5 tfe: backing services + imds-proxy + Helm release"
terraform -chdir="$ROOT/tfe" init -input=false
"$ROOT/scripts/set-cluster-auth.sh"
terraform -chdir="$ROOT/tfe" apply -auto-approve -input=false

echo
log "DONE. TFE: $(terraform -chdir="$ROOT/tfe" output -raw tfe_url)"
log "Initial admin token: $OC exec -it -n tfe deploy/terraform-enterprise -- tfectl admin token"
