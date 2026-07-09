#!/usr/bin/env bash
# =============================================================================
# create_tfe_secrets.sh
# Creates the Secrets Manager secrets required by the TFE HVD modules. Generates
# a self-signed CA + a wildcard TLS cert for the hosted zone, so a single cert
# serves every TFE subdomain under it (e.g. tfe-demo.<zone> and
# tfe-eks-demo.<zone> from the EC2 and EKS deployments).
#
# Secrets that already exist are left untouched by default, so re-running is
# safe. Pass --rotate to overwrite existing values — do NOT do this against a
# live TFE deployment: it rotates the encryption and database passwords
# without updating the running instance or RDS, which will break TFE.
#
# Prerequisites:
#   - aws cli (configured with appropriate credentials/profile)
#   - openssl
#
# Required env vars:
#   TFE_HOSTED_ZONE     Route53 hosted zone the cert covers, e.g. example.com
#                       (the cert is issued for *.<zone> and <zone>)
#   AWS_REGION          e.g. ap-southeast-1
#   SECRET_PREFIX       e.g. tfe-demo
#   TFE_LICENSE_PATH    path to your .hclic file
#
# Usage:
#   ./create_tfe_secrets.sh [--rotate]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Logs go to stderr so ARNs captured via $(create_or_update_secret ...) on
# stdout stay clean.
log()  { echo "[INFO]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || die "'$cmd' not found — please install it first."
  done
}

create_or_update_secret() {
  local name="$1"
  local description="$2"
  local value_flag="$3"
  local value="$4"

  if aws secretsmanager describe-secret --secret-id "$name" \
       --region "$AWS_REGION" &>/dev/null 2>&1; then
    if [[ "$ROTATE" == "true" ]]; then
      log "Secret '$name' already exists — rotating value (--rotate)."
      aws secretsmanager put-secret-value \
        --secret-id "$name" \
        --region "$AWS_REGION" \
        "$value_flag" "$value" \
        --output text --query 'ARN'
    else
      log "Secret '$name' already exists — skipping (pass --rotate to overwrite)."
      aws secretsmanager describe-secret \
        --secret-id "$name" \
        --region "$AWS_REGION" \
        --output text --query 'ARN'
    fi
  else
    log "Creating secret '$name'."
    aws secretsmanager create-secret \
      --name "$name" \
      --description "$description" \
      --region "$AWS_REGION" \
      "$value_flag" "$value" \
      --output text --query 'ARN'
  fi
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
ROTATE=false
for arg in "$@"; do
  case "$arg" in
    --rotate) ROTATE=true ;;
    *) die "Unknown argument: '$arg' (usage: $0 [--rotate])" ;;
  esac
done

if [[ "$ROTATE" == "true" ]]; then
  log "--rotate: existing secrets WILL be overwritten with new values."
  log "Do NOT do this against a live TFE deployment — rotating the encryption"
  log "and database passwords without updating TFE/RDS will break it."
  read -r -p "Type 'rotate' to continue: " confirm
  [[ "$confirm" == "rotate" ]] || die "Aborted."
fi

# ---------------------------------------------------------------------------
# Preflight: required env vars
# ---------------------------------------------------------------------------
require aws openssl

[[ -z "${TFE_HOSTED_ZONE:-}"  ]] && die "TFE_HOSTED_ZONE is not set."
[[ -z "${AWS_REGION:-}"       ]] && die "AWS_REGION is not set."
[[ -z "${SECRET_PREFIX:-}"    ]] && die "SECRET_PREFIX is not set."
[[ -z "${TFE_LICENSE_PATH:-}" ]] && die "TFE_LICENSE_PATH is not set."
[[ -f "$TFE_LICENSE_PATH"     ]] || die "TFE_LICENSE_PATH file not found: $TFE_LICENSE_PATH"

TFE_LICENSE_CONTENT="$(cat "$TFE_LICENSE_PATH")"

# Wildcard cert covers every single-label subdomain under the zone.
WILDCARD_DOMAIN="*.${TFE_HOSTED_ZONE}"

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

log "Hosted zone:   $TFE_HOSTED_ZONE"
log "Cert domains:  $WILDCARD_DOMAIN, $TFE_HOSTED_ZONE"
log "AWS region:    $AWS_REGION"
log "Secret prefix: $SECRET_PREFIX"
log "License file:  $TFE_LICENSE_PATH"
echo

# ---------------------------------------------------------------------------
# Generate passwords
# ---------------------------------------------------------------------------
ENCRYPTION_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
log "Generated encryption password."

DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!#%^&*()_-' | head -c 24)"
log "Generated database password."

# charset per ElastiCache auth-token rules: no @, " or /
REDIS_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!#%^&*()_-' | head -c 24)"
log "Generated Redis password."

# ---------------------------------------------------------------------------
# Self-signed CA + TLS cert + private key
# ---------------------------------------------------------------------------
CA_KEY="$TMPDIR_WORK/ca.key"
CA_CERT="$TMPDIR_WORK/ca.crt"
TLS_KEY="$TMPDIR_WORK/tfe.key"
TLS_CSR="$TMPDIR_WORK/tfe.csr"
TLS_CERT="$TMPDIR_WORK/tfe.crt"
EXT_FILE="$TMPDIR_WORK/tfe.ext"

log "Generating self-signed CA..."
openssl genrsa -out "$CA_KEY" 4096 2>/dev/null
openssl req -x509 -new -nodes \
  -key "$CA_KEY" \
  -sha256 -days 3650 \
  -subj "/C=SG/O=HashiCorp Demo/CN=TFE Demo CA" \
  -out "$CA_CERT" 2>/dev/null

log "Generating TLS private key + CSR for $WILDCARD_DOMAIN..."
openssl genrsa -out "$TLS_KEY" 4096 2>/dev/null
openssl req -new \
  -key "$TLS_KEY" \
  -subj "/C=SG/O=HashiCorp Demo/CN=${WILDCARD_DOMAIN}" \
  -out "$TLS_CSR" 2>/dev/null

# SAN covers the wildcard (any single-label subdomain) plus the bare apex.
cat > "$EXT_FILE" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${WILDCARD_DOMAIN}
DNS.2 = ${TFE_HOSTED_ZONE}
EOF

log "Signing TLS cert with the demo CA..."
openssl x509 -req \
  -in "$TLS_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$TLS_CERT" \
  -days 825 \
  -sha256 \
  -extfile "$EXT_FILE" 2>/dev/null

log "Verifying cert chain..."
openssl verify -CAfile "$CA_CERT" "$TLS_CERT" >/dev/null

# ---------------------------------------------------------------------------
# base64-encode the PEM files (single line, no line wrapping)
# The HVD module expects base64-encoded strings, not raw PEM.
# ---------------------------------------------------------------------------
TLS_CERT_B64="$(base64 < "$TLS_CERT" | tr -d '\n')"
TLS_KEY_B64="$(base64 < "$TLS_KEY"   | tr -d '\n')"
CA_BUNDLE_B64="$(base64 < "$CA_CERT" | tr -d '\n')"

# ---------------------------------------------------------------------------
# Push to Secrets Manager
# ---------------------------------------------------------------------------
echo
log "=== Creating / updating Secrets Manager secrets ==="
echo

ARN_LICENSE="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-license" \
  "TFE license (.hclic contents)" \
  "--secret-string" "$TFE_LICENSE_CONTENT")"
log "tfe_license_secret_arn             = $ARN_LICENSE"

ARN_ENC_PW="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-encryption-password" \
  "TFE encryption password" \
  "--secret-string" "$ENCRYPTION_PASSWORD")"
log "tfe_encryption_password_secret_arn = $ARN_ENC_PW"

ARN_DB_PW="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-database-password" \
  "TFE RDS database password" \
  "--secret-string" "$DB_PASSWORD")"
log "tfe_database_password_secret_arn   = $ARN_DB_PW"

ARN_REDIS_PW="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-redis-password" \
  "TFE Redis password" \
  "--secret-string" "$REDIS_PASSWORD")"
log "tfe_redis_password_secret_arn      = $ARN_REDIS_PW"

ARN_TLS_CERT="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-tls-cert" \
  "TFE TLS certificate (base64-encoded PEM)" \
  "--secret-string" "$TLS_CERT_B64")"
log "tfe_tls_cert_secret_arn            = $ARN_TLS_CERT"

ARN_TLS_KEY="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-tls-privkey" \
  "TFE TLS private key (base64-encoded PEM)" \
  "--secret-string" "$TLS_KEY_B64")"
log "tfe_tls_privkey_secret_arn         = $ARN_TLS_KEY"

ARN_CA_BUNDLE="$(create_or_update_secret \
  "${SECRET_PREFIX}/tfe-tls-ca-bundle" \
  "TFE TLS CA bundle (base64-encoded PEM)" \
  "--secret-string" "$CA_BUNDLE_B64")"
log "tfe_tls_ca_bundle_secret_arn       = $ARN_CA_BUNDLE"

echo
log "Done. Retrieve ARNs from Secrets Manager or the log output above."