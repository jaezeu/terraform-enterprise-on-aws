#!/usr/bin/env bash
# =============================================================================
# destroy.sh — tear the whole stack down: tfe -> config -> cluster, then the
# local install artifacts. The reverse of deploy.sh, in one command.
#
# Needs a fresh AWS session (aws login) and terraform login, nothing else.
# Layers that were never applied destroy as no-ops, so this is safe to run
# from any half-built state.
# =============================================================================

set -euo pipefail

log() { echo; echo "===== [destroy] $* ====="; }
die() { echo "[ERROR] $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"

aws sts get-caller-identity >/dev/null 2>&1 || die "no AWS session — run: aws login"

echo "This destroys the OpenShift cluster, TFE, and ALL their data (RDS, S3, DNS)."
read -r -p "Type 'destroy' to continue: " answer
[[ "$answer" == "destroy" ]] || die "aborted."

log "1/4 tfe (Helm release, RDS, Redis, S3, DNS record)"
terraform -chdir="$ROOT/tfe" init -input=false
terraform -chdir="$ROOT/tfe" destroy -auto-approve -input=false

log "2/4 config (*.apps DNS records)"
terraform -chdir="$ROOT/config" init -input=false
terraform -chdir="$ROOT/config" destroy -auto-approve -input=false

log "3/4 cluster (VPC, nodes, LBs, IAM, DNS)"
# The in-cluster cloud controller created the router load balancer (and its
# security groups) outside Terraform — delete them first or they block the
# subnet/IGW/VPC deletions. Tagged kubernetes.io/cluster/<infra_id>=owned.
if [[ -f "$ROOT/cluster/cluster.auto.tfvars.json" ]]; then
  INFRA_ID="$(jq -r .infra_id "$ROOT/cluster/cluster.auto.tfvars.json")"
  for lb in $(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text); do
    tagged="$(aws elb describe-tags --load-balancer-names "$lb" \
      --query "TagDescriptions[0].Tags[?Key=='kubernetes.io/cluster/$INFRA_ID'] | [0].Value" --output text)"
    if [[ "$tagged" == "owned" ]]; then
      echo "deleting cluster-created ELB: $lb"
      aws elb delete-load-balancer --load-balancer-name "$lb"
    fi
  done
  for sg in $(aws ec2 describe-security-groups \
      --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    # a deleted ELB's ENIs are requester-managed — nothing can force-delete
    # them; wait (up to ~8 min) until the ELB releases them, then delete the SG
    echo "waiting for $sg to have no attached network interfaces..."
    for _ in $(seq 1 24); do
      n="$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$sg" \
        --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo 1)"
      [[ "$n" == "0" ]] && break
      sleep 20
    done
    echo "deleting cluster-created security group: $sg"
    aws ec2 delete-security-group --group-id "$sg" \
      || echo "WARNING: could not delete $sg — the VPC destroy below may fail on it; delete it manually and re-run: terraform -chdir=cluster destroy"
  done
fi
terraform -chdir="$ROOT/cluster" init -input=false
terraform -chdir="$ROOT/cluster" destroy -auto-approve -input=false

log "4/4 local artifacts (ignition is single-use — a rebuild needs a fresh bootstrap.sh)"
if [[ -f "$ROOT/cluster/cluster.auto.tfvars.json" ]]; then
  IGN_BUCKET="$(jq -r .bootstrap_ign_bucket "$ROOT/cluster/cluster.auto.tfvars.json")"
  aws s3 rb "s3://$IGN_BUCKET" --force 2>/dev/null || true # already gone if deploy.sh finished
fi
rm -rf "$ROOT/install-dir" "$ROOT/cluster/ccoctl-generated" "$ROOT/cluster/cluster.auto.tfvars.json"

log "DONE. Rebuild any time with ./deploy.sh"
