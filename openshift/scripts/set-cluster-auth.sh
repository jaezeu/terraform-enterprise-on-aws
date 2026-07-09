#!/usr/bin/env bash
# =============================================================================
# set-cluster-auth.sh — push the cluster's system:admin credentials to the
# tfe-hvd-ocp-tfe workspace as sensitive Terraform variables.
#
# The kubernetes/helm providers in the tfe layer authenticate with the client
# certificate from openshift/install-dir/auth/kubeconfig (issued by the
# installer, valid ~10 years). Run this once per cluster build — a new
# cluster means a new kubeconfig, so re-run it after every bootstrap.sh.
#
# Values go directly from the kubeconfig to HCP Terraform; nothing is printed.
# Requires: terraform login (uses ~/.terraform.d/credentials.tfrc.json), jq.
# =============================================================================

set -euo pipefail

ORG="jaz-hashi"
WORKSPACE="tfe-hvd-ocp-tfe"
KUBECONFIG_FILE="$(cd "$(dirname "$0")/.." && pwd)/install-dir/auth/kubeconfig"

[[ -f "$KUBECONFIG_FILE" ]] || { echo "[ERROR] $KUBECONFIG_FILE not found — run scripts/bootstrap.sh first." >&2; exit 1; }

TOKEN="$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)"
WS_ID="$(curl -sfS -H "Authorization: Bearer $TOKEN" \
  "https://app.terraform.io/api/v2/organizations/$ORG/workspaces/$WORKSPACE" | jq -r .data.id)"

# The workspace may already hold a var from a previous cluster — PATCH it
# instead of POSTing a duplicate.
EXISTING="$(curl -sfS -H "Authorization: Bearer $TOKEN" \
  "https://app.terraform.io/api/v2/workspaces/$WS_ID/vars")"

# var name : kubeconfig field (plain pairs — macOS bash 3.2 has no declare -A)
for pair in \
  "cluster_ca_certificate:certificate-authority-data" \
  "cluster_client_certificate:client-certificate-data" \
  "cluster_client_key:client-key-data"; do
  var="${pair%%:*}"
  field="${pair##*:}"
  value="$(awk -v f="$field:" '$1 == f {print $2; exit}' "$KUBECONFIG_FILE")"
  [[ -n "$value" ]] || { echo "[ERROR] $field not found in kubeconfig." >&2; exit 1; }

  var_id="$(jq -r --arg k "$var" '.data[] | select(.attributes.key == $k) | .id' <<<"$EXISTING")"
  payload="$(jq -n --arg k "$var" --arg v "$value" \
    '{data:{type:"vars",attributes:{key:$k,value:$v,category:"terraform",sensitive:true,description:"system:admin auth from install-dir kubeconfig (set-cluster-auth.sh)"}}}')"

  if [[ -n "$var_id" ]]; then
    curl -sfS -o /dev/null -X PATCH -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/vnd.api+json" -d "$payload" \
      "https://app.terraform.io/api/v2/workspaces/$WS_ID/vars/$var_id"
    echo "[INFO]  updated $var"
  else
    curl -sfS -o /dev/null -X POST -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/vnd.api+json" -d "$payload" \
      "https://app.terraform.io/api/v2/workspaces/$WS_ID/vars"
    echo "[INFO]  created $var"
  fi
done

echo "[INFO]  Done. The $WORKSPACE workspace can now reach the cluster."
