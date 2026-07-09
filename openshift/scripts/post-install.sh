#!/usr/bin/env bash
# =============================================================================
# post-install.sh — everything between "bootstrap node removed" and a healthy
# cluster: approves node CSRs (workers need two rounds), sets image-registry
# storage to emptyDir (no S3 — pods can't reach IMDS for AWS creds), applies
# the config layer's *.apps DNS as soon as the router's LB exists (must happen
# DURING the wait: auth/console only go Available once their routes resolve,
# and install-complete waits on them), then waits for install-complete.
#
# Run after: terraform apply -var bootstrap_enabled=false
# =============================================================================

set -euo pipefail

log() { echo "[INFO]  $*" >&2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)" # openshift/
BIN_DIR="$ROOT/.bin"
INSTALL_DIR="$ROOT/install-dir"
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"

REGISTRY_PATCH='{"spec":{"managementState":"Managed","storage":{"s3":null,"emptyDir":{}}}}'
registry_done=""
apps_dns_done=""
tick=0

log "Waiting for install-complete (approving CSRs, configuring registry, wiring *.apps DNS)..."
"$BIN_DIR/openshift-install" wait-for install-complete --dir "$INSTALL_DIR" &
WAIT_PID=$!

while kill -0 "$WAIT_PID" 2>/dev/null; do
  pending="$("$BIN_DIR/oc" get csr -o json 2>/dev/null | jq -r '.items[] | select(.status == {}) | .metadata.name' || true)"
  if [[ -n "$pending" ]]; then
    echo "$pending" | xargs "$BIN_DIR/oc" adm certificate approve || true
  fi

  if [[ -z "$registry_done" ]] && "$BIN_DIR/oc" patch configs.imageregistry.operator.openshift.io/cluster \
      --type merge -p "$REGISTRY_PATCH" 2>/dev/null; then
    registry_done=1
    log "image-registry storage set to emptyDir."
  fi

  if [[ -z "$apps_dns_done" ]]; then
    APPS_LB="$("$BIN_DIR/oc" -n openshift-ingress get svc router-default \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    if [[ -n "$APPS_LB" ]]; then
      log "Router LB is up ($APPS_LB) — creating *.apps DNS records..."
      terraform -chdir="$ROOT/config" init -input=false >/dev/null
      terraform -chdir="$ROOT/config" apply -auto-approve -input=false \
        -var "apps_lb_hostname=$APPS_LB" && apps_dns_done=1
    fi
  fi

  # heartbeat every ~2 min so the quiet operator-rollout phase isn't mistaken
  # for a hang
  tick=$((tick + 1))
  if ((tick % 4 == 0)); then
    waiting="$("$BIN_DIR/oc" get clusteroperators -o json 2>/dev/null | jq -r \
      '[.items[] | select(([.status.conditions[]? | select(.type=="Available" and .status=="True")] | length) == 0) | .metadata.name] | join(", ")' || true)"
    [[ -n "$waiting" ]] && log "still waiting on operators: $waiting"
  fi

  sleep 30
done
wait "$WAIT_PID"   # propagate the installer's exit code

echo
log "Install complete: $(terraform -chdir="$ROOT/config" output -raw console_url)"
log "Login: kubeadmin / $(cat "$INSTALL_DIR/auth/kubeadmin-password")"
log "Next: delete the ignition bucket (secrets, no longer needed):"
log "  aws s3 rb s3://$(jq -r .bootstrap_ign_bucket "$ROOT/cluster/cluster.auto.tfvars.json") --force"
