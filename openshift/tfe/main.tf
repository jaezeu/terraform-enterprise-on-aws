# =============================================================================
# Layer 3: TFE application — Kubernetes secrets + the terraform-enterprise
# Helm chart, mirroring eks/tfe with the OpenShift-specific differences:
#   - anyuid SCC grant instead of the chart's openshift mode (see below)
#   - no IRSA: S3 auth is node-role credentials via the imds-proxy
#   - no external-dns: dns.tf creates the Route 53 record from the LB hostname
# =============================================================================

locals {
  tfe_namespace = "tfe"
  tfe_registry  = "images.releases.hashicorp.com"
  tfe_license   = data.aws_secretsmanager_secret_version.tfe["license"].secret_string
}

# -----------------------------------------------------------------------------
# Kubernetes secrets required by the TFE chart: image pull secret, TFE config
# secrets, TLS certs (the *.<base_domain> wildcard from Secrets Manager).
# -----------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "tfe" {
  metadata {
    name = local.tfe_namespace
  }

  # OpenShift stamps SCC uid/mcs ranges onto every namespace
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_secret_v1" "tfe_image_pull" {
  metadata {
    name      = "terraform-enterprise" # chart's default imagePullSecrets name
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.tfe_registry) = {
          username = "terraform"
          password = local.tfe_license # the TFE license is the registry password
          auth     = base64encode("terraform:${local.tfe_license}")
        }
      }
    })
  }
}

resource "kubernetes_secret_v1" "tfe_secrets" {
  metadata {
    name      = "tfe-secrets"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  data = {
    TFE_LICENSE             = local.tfe_license
    TFE_ENCRYPTION_PASSWORD = data.aws_secretsmanager_secret_version.tfe["encryption_password"].secret_string
    TFE_DATABASE_PASSWORD   = data.aws_secretsmanager_secret_version.tfe["database_password"].secret_string
    TFE_REDIS_PASSWORD      = data.aws_secretsmanager_secret_version.tfe["redis_password"].secret_string
  }
}

resource "kubernetes_secret_v1" "tfe_certs" {
  metadata {
    name      = "tfe-certs"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  type = "kubernetes.io/tls"

  # Secrets Manager stores the PEMs base64-encoded; the kubernetes provider
  # expects raw PEM in `data` (it handles the base64 encoding itself).
  data = {
    "tls.crt" = base64decode(data.aws_secretsmanager_secret_version.tfe["tls_cert"].secret_string)
    "tls.key" = base64decode(data.aws_secretsmanager_secret_version.tfe["tls_privkey"].secret_string)
  }
}

# -----------------------------------------------------------------------------
# TFE application
# -----------------------------------------------------------------------------

# The TFE image must run as its built-in `tfe` user with sudo available: its
# service-setup creates scratch dirs and installs the CA bundle via sudo,
# which the restricted-v2 SCC's random UID + no-new-privileges forbids
# (openshift.enabled=true crashes at startup on this image). anyuid lets the
# pod run exactly as it does on EKS. Demo trade-off, scoped to this one SA.
resource "kubernetes_role_binding_v1" "tfe_scc_anyuid" {
  metadata {
    name      = "tfe-scc-anyuid"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:openshift:scc:anyuid"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "tfe"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }
}

resource "helm_release" "terraform_enterprise" {
  depends_on = [kubernetes_role_binding_v1.tfe_scc_anyuid]

  name       = "terraform-enterprise"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "terraform-enterprise"
  namespace  = kubernetes_namespace_v1.tfe.metadata[0].name

  # first TFE boot runs database migrations — give the wait ample time
  wait    = true
  timeout = 1800

  values = [yamlencode({
    # NOT openshift.enabled=true — see the anyuid role binding above; agent
    # pods get OpenShift compat via TFE_RUN_PIPELINE_KUBERNETES_* below.
    serviceAccount = {
      enabled = true
      name    = "tfe" # the anyuid grant above is bound to this name
    }

    # The chart default requests 4 CPU — never schedulable on an m6i.xlarge
    # worker (4 vCPU minus OpenShift system reservations).
    resources = {
      requests = { cpu = "2", memory = "8Gi" }
    }

    tls = {
      certificateSecret = kubernetes_secret_v1.tfe_certs.metadata[0].name
      caCertData        = data.aws_secretsmanager_secret_version.tfe["tls_ca_bundle"].secret_string # already base64-encoded PEM
    }

    image = {
      repository = local.tfe_registry
      name       = "hashicorp/terraform-enterprise"
      tag        = var.tfe_image_tag
    }

    imagePullSecrets = [{ name = kubernetes_secret_v1.tfe_image_pull.metadata[0].name }]

    # The cloud controller manager provisions a classic ELB for this;
    # dns.tf points the TFE hostname at it.
    service = {
      type = "LoadBalancer"
      port = 443
    }

    env = {
      secretRefs = [{ name = kubernetes_secret_v1.tfe_secrets.metadata[0].name }]

      variables = {
        TFE_HOSTNAME = local.tfe_fqdn

        # Database
        TFE_DATABASE_HOST       = aws_db_instance.tfe.endpoint # host:port
        TFE_DATABASE_NAME       = aws_db_instance.tfe.db_name
        TFE_DATABASE_USER       = aws_db_instance.tfe.username
        TFE_DATABASE_PARAMETERS = "sslmode=require"

        # Object storage: node-role credentials via the imds-proxy
        AWS_EC2_METADATA_SERVICE_ENDPOINT            = "http://${kubernetes_service_v1.imds_proxy.metadata[0].name}.${local.tfe_namespace}.svc.cluster.local"
        TFE_OBJECT_STORAGE_TYPE                      = "s3"
        TFE_OBJECT_STORAGE_S3_BUCKET                 = aws_s3_bucket.tfe.bucket
        TFE_OBJECT_STORAGE_S3_REGION                 = data.aws_region.current.region
        TFE_OBJECT_STORAGE_S3_USE_INSTANCE_PROFILE   = true
        TFE_OBJECT_STORAGE_S3_SERVER_SIDE_ENCRYPTION = "AES256"

        # Redis (auth + TLS match the replication group in backing.tf)
        TFE_REDIS_HOST     = aws_elasticache_replication_group.tfe.primary_endpoint_address
        TFE_REDIS_USE_AUTH = true
        TFE_REDIS_USE_TLS  = true

        # agent (run) pods still run under restricted-v2
        TFE_RUN_PIPELINE_KUBERNETES_OPEN_SHIFT_ENABLED = true
      }
    }
  })]
}
