#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — out-of-band UPI prep (run locally with AWS credentials).
#
# 1. Downloads openshift-install + oc (native) and ccoctl (linux, run in docker)
# 2. Renders install-config.yaml (credentialsMode: Manual — STS/roles, no IAM users)
# 3. ccoctl: OIDC provider + per-operator IAM roles from the release's CredentialsRequests
# 4. Generates manifests (+ ccoctl output) and ignition configs (install-dir/ — gitignored)
# 5. Extracts what Terraform needs into cluster/cluster.auto.tfvars.json
# 6. Creates a small S3 bucket and uploads bootstrap.ign (too big for user-data)
#
# After this: terraform init && terraform apply in cluster/.
#
# Required env vars:
#   OCP_BASE_DOMAIN    e.g. example.com (public Route53 zone)
#   OCP_CLUSTER_NAME   e.g. tfe-ocp
#   AWS_REGION         e.g. ap-southeast-1
#   PULL_SECRET_PATH   path to pull-secret.txt from console.redhat.com
# Optional:
#   OCP_VERSION        default: stable (e.g. 4.22.2)
# =============================================================================

set -euo pipefail

log() { echo "[INFO]  $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

for v in OCP_BASE_DOMAIN OCP_CLUSTER_NAME AWS_REGION PULL_SECRET_PATH; do
  [[ -z "${!v:-}" ]] && die "$v is not set."
done
[[ -f "$PULL_SECRET_PATH" ]] || die "pull secret not found: $PULL_SECRET_PATH"
command -v aws >/dev/null || die "aws CLI required"
command -v jq  >/dev/null || die "jq required"

OCP_VERSION="${OCP_VERSION:-stable}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)" # openshift/
BIN_DIR="$ROOT/.bin"
INSTALL_DIR="$ROOT/install-dir"
CLUSTER_DIR="$ROOT/cluster"
MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}"

# ---------------------------------------------------------------------------
# 1. Tooling (arch-aware)
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  INST_TAR="openshift-install-mac-arm64.tar.gz"; OC_TAR="openshift-client-mac-arm64.tar.gz" ;;
  Darwin-x86_64) INST_TAR="openshift-install-mac.tar.gz";       OC_TAR="openshift-client-mac.tar.gz" ;;
  Linux-x86_64)  INST_TAR="openshift-install-linux.tar.gz";     OC_TAR="openshift-client-linux.tar.gz" ;;
  *) die "unsupported platform: $(uname -s)-$(uname -m)" ;;
esac

if [[ ! -x "$BIN_DIR/openshift-install" ]]; then
  log "Downloading openshift-install ($OCP_VERSION)..."
  curl -sfL "$MIRROR/$INST_TAR" | tar -xz -C "$BIN_DIR" openshift-install
fi
if [[ ! -x "$BIN_DIR/oc" ]]; then
  log "Downloading oc..."
  curl -sfL "$MIRROR/$OC_TAR" | tar -xz -C "$BIN_DIR" oc
fi

# ccoctl (Cloud Credential Operator tool) is Linux-only; on macOS we run it in
# a linux/amd64 container (see run_ccoctl below).
if [[ ! -f "$BIN_DIR/ccoctl" ]]; then
  log "Downloading ccoctl (linux)..."
  curl -sfL "$MIRROR/ccoctl-linux.tar.gz" | tar -xz -C "$BIN_DIR" ccoctl
fi

# Runs ccoctl with $INSTALL_DIR as the working directory (mounted at /work in
# the container on macOS) — always pass INSTALL_DIR-relative paths.
run_ccoctl() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    command -v docker >/dev/null || die "docker required to run ccoctl on macOS (colima start)"
    docker run --rm --platform linux/amd64 \
      -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION \
      -v "$BIN_DIR/ccoctl:/usr/local/bin/ccoctl:ro" -v "$INSTALL_DIR:/work" -w /work \
      registry.access.redhat.com/ubi9/ubi-minimal:latest ccoctl "$@"
  else
    (cd "$INSTALL_DIR" && "$BIN_DIR/ccoctl" "$@")
  fi
}

# macOS SIGKILLs Go binaries whose ad-hoc signature is invalidated by tar
# extraction ("Killed: 9"). A forced ad-hoc re-sign fixes them.
if [[ "$(uname -s)" == "Darwin" ]]; then
  codesign --force --sign - "$BIN_DIR/openshift-install" "$BIN_DIR/oc" 2>/dev/null || true
fi

"$BIN_DIR/openshift-install" version >/dev/null || die "openshift-install failed to execute"
log "openshift-install: $("$BIN_DIR/openshift-install" version | head -1)"

# ---------------------------------------------------------------------------
# 2. SSH key + install-config
# ---------------------------------------------------------------------------
if [[ ! -f "$ROOT/ocp-ssh-key" ]]; then
  log "Generating SSH key for node access..."
  ssh-keygen -t ed25519 -N "" -q -f "$ROOT/ocp-ssh-key" -C "ocp-node-debug"
fi

if [[ -d "$INSTALL_DIR" ]]; then
  die "install-dir/ already exists. A cluster's ignition is single-use: to start over, destroy the cluster, then 'rm -rf install-dir cluster/cluster.auto.tfvars.json' and re-run."
fi
mkdir -p "$INSTALL_DIR"

log "Rendering install-config.yaml..."
PULL_SECRET_JSON="$(jq -c . "$PULL_SECRET_PATH")"
SSH_PUB="$(cat "$ROOT/ocp-ssh-key.pub")"
sed -e "s|__BASE_DOMAIN__|$OCP_BASE_DOMAIN|" \
    -e "s|__CLUSTER_NAME__|$OCP_CLUSTER_NAME|" \
    -e "s|__REGION__|$AWS_REGION|" \
    -e "s|__PULL_SECRET__|$(printf '%s' "$PULL_SECRET_JSON" | sed 's/[&|]/\\&/g')|" \
    -e "s|__SSH_KEY__|$SSH_PUB|" \
    "$ROOT/templates/install-config.template.yaml" > "$INSTALL_DIR/install-config.yaml"

# ---------------------------------------------------------------------------
# 3. Cloud credentials (credentialsMode: Manual) — ccoctl dry-run emits the
#    per-operator role/policy artifacts; cluster/identity.tf creates the roles.
# ---------------------------------------------------------------------------
RELEASE_IMAGE="$("$BIN_DIR/openshift-install" version | awk '/release image/ {print $3}')"
log "Extracting CredentialsRequests from $RELEASE_IMAGE..."
"$BIN_DIR/oc" adm release extract --credentials-requests --included \
  --install-config="$INSTALL_DIR/install-config.yaml" \
  --to="$INSTALL_DIR/credreqs" -a "$PULL_SECRET_PATH" "$RELEASE_IMAGE"

log "Running ccoctl aws create-all --dry-run (emits artifacts; Terraform creates the AWS resources)..."
run_ccoctl aws create-all --dry-run \
  --name "$OCP_CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --credentials-requests-dir credreqs \
  --output-dir ccoctl-out

# Copy the role/policy pairs (05/06) where identity.tf can read them during
# remote runs. No OIDC artifacts needed — identity.tf role-chains off the
# node roles instead (the SCP denies self-hosted OIDC providers).
rm -rf "$CLUSTER_DIR/ccoctl-generated" && mkdir -p "$CLUSTER_DIR/ccoctl-generated"
cp "$INSTALL_DIR"/ccoctl-out/0[5-6]-* "$CLUSTER_DIR/ccoctl-generated/"

# Rewrite credential manifests for IMDS role chaining: fill in the role ARNs
# identity.tf will create (same name, truncated to 64 chars like ccoctl does),
# swap web_identity_token_file for credential_source = Ec2InstanceMetadata,
# and drop the invalid-YAML sentinel line the dry-run appends.
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
for m in "$INSTALL_DIR"/ccoctl-out/manifests/*-credentials.yaml; do
  role="${OCP_CLUSTER_NAME}-$(basename "$m" -credentials.yaml)"
  role="${role:0:64}"
  sed -i.bak \
    -e "s|role_arn =.*|role_arn = arn:aws:iam::${ACCOUNT_ID}:role/${role}|" \
    -e "s|web_identity_token_file =.*|credential_source = Ec2InstanceMetadata|" \
    -e '/POPULATE ROLE ARN AND DELETE THIS LINE/d' \
    "$m" && rm -f "$m.bak"
done
log "Rewrote $(ls "$INSTALL_DIR"/ccoctl-out/manifests/*-credentials.yaml | wc -l | tr -d ' ') credential manifests for IMDS role chaining."

# ---------------------------------------------------------------------------
# 4. Manifests + ignition configs
# ---------------------------------------------------------------------------
# Only the credential Secrets come from ccoctl — its Authentication CR and
# signing key serve OIDC federation, which the SCP rules out.
log "Generating manifests and folding in ccoctl credential secrets..."
"$BIN_DIR/openshift-install" create manifests --dir "$INSTALL_DIR"
cp "$INSTALL_DIR"/ccoctl-out/manifests/*-credentials.yaml "$INSTALL_DIR/manifests/"

# UPI manifest surgery — Terraform owns machines and DNS (pod-network
# operators can't reach IMDS for AWS creds anyway): drop the machine-api
# manifests, and detach the Route53 zones so the ingress operator doesn't
# try (and fail) to publish *.apps records.
log "Removing machine-api manifests and DNS zones (UPI: Terraform owns these)..."
rm -f "$INSTALL_DIR"/openshift/99_openshift-cluster-api_master-machines-*.yaml \
      "$INSTALL_DIR"/openshift/99_openshift-cluster-api_worker-machineset-*.yaml \
      "$INSTALL_DIR"/openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml
awk '/^  (privateZone|publicZone):/ {skip=1; next} skip && /^    / {next} {skip=0; print}' \
  "$INSTALL_DIR/manifests/cluster-dns-02-config.yml" > "$INSTALL_DIR/manifests/cluster-dns-02-config.yml.tmp" \
  && mv "$INSTALL_DIR/manifests/cluster-dns-02-config.yml.tmp" "$INSTALL_DIR/manifests/cluster-dns-02-config.yml"

log "Generating ignition configs..."
"$BIN_DIR/openshift-install" create ignition-configs --dir "$INSTALL_DIR"

INFRA_ID="$(jq -r .infraID "$INSTALL_DIR/metadata.json")"
IGN_CA="$(jq -r '.ignition.security.tls.certificateAuthorities[0].source' "$INSTALL_DIR/master.ign")"
log "infra_id: $INFRA_ID"

# ---------------------------------------------------------------------------
# 5. RHCOS AMI for this region, from the installer itself (always matching)
# ---------------------------------------------------------------------------
AMI="$("$BIN_DIR/openshift-install" coreos print-stream-json \
  | jq -r ".architectures.x86_64.images.aws.regions[\"$AWS_REGION\"].image")"
[[ "$AMI" == ami-* ]] || die "could not resolve RHCOS AMI for $AWS_REGION"
log "rhcos ami: $AMI"

# ---------------------------------------------------------------------------
# 6. Bootstrap ignition -> S3 (too large for EC2 user-data)
# ---------------------------------------------------------------------------
IGN_BUCKET="${INFRA_ID}-bootstrap-ign"
log "Creating s3://$IGN_BUCKET and uploading bootstrap.ign..."
aws s3 mb "s3://$IGN_BUCKET" --region "$AWS_REGION" >/dev/null
aws s3 cp "$INSTALL_DIR/bootstrap.ign" "s3://$IGN_BUCKET/bootstrap.ign" --region "$AWS_REGION" >/dev/null

# ---------------------------------------------------------------------------
# 7. Terraform inputs (no secrets: infra id, AMI, public CA cert, names)
# ---------------------------------------------------------------------------
jq -n \
  --arg infra_id "$INFRA_ID" \
  --arg ami "$AMI" \
  --arg ign_ca "$IGN_CA" \
  --arg cluster_name "$OCP_CLUSTER_NAME" \
  --arg base_domain "$OCP_BASE_DOMAIN" \
  --arg ign_bucket "$IGN_BUCKET" \
  '{infra_id:$infra_id, rhcos_ami:$ami, ignition_ca:$ign_ca, cluster_name:$cluster_name, base_domain:$base_domain, bootstrap_ign_bucket:$ign_bucket}' \
  > "$CLUSTER_DIR/cluster.auto.tfvars.json"

log "Wrote cluster/cluster.auto.tfvars.json"
echo
log "Next steps (deploy.sh runs all of these):"
log "  1. terraform -chdir=cluster init && terraform -chdir=cluster apply    # ~5 min"
log "  2. .bin/openshift-install wait-for bootstrap-complete --dir install-dir   # ~15-20 min"
log "  3. terraform -chdir=cluster apply -var bootstrap_enabled=false   # remove bootstrap node"
log "  4. scripts/post-install.sh   # CSRs + registry + install-complete   # ~20-30 min"
log "  5. aws s3 rb s3://$IGN_BUCKET --force --region $AWS_REGION   # ignition no longer needed"
