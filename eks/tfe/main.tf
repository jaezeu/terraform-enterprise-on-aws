# Layer 3: TFE application — Kubernetes secrets + the terraform-enterprise
# Helm chart, applied after addons. Values mirror the HVD module's
# helm_overrides template, populated from infra outputs. DNS comes from
# external-dns (addons layer) via the Service's hostname annotation.

locals {
  # local.infra: see data.tf

  # Must match the HVD module defaults (tfe_kube_namespace /
  # tfe_kube_svc_account) — the TFE IRSA trust policy is bound to this pair.
  tfe_namespace        = "tfe"
  tfe_kube_svc_account = "tfe"

  tfe_registry = "images.releases.hashicorp.com"
  tfe_license  = data.aws_secretsmanager_secret_version.tfe["license"].secret_string
}

# -----------------------------------------------------------------------------
# Kubernetes secrets required by the TFE chart (per the module's
# docs/kubernetes-secrets.md): image pull secret, TFE config secrets, TLS certs.
# -----------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "tfe" {
  metadata {
    name = local.tfe_namespace
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
resource "helm_release" "terraform_enterprise" {
  name       = "terraform-enterprise"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "terraform-enterprise"
  namespace  = kubernetes_namespace_v1.tfe.metadata[0].name

  # first TFE boot runs database migrations — give the wait ample time
  wait    = true
  timeout = 1800

  values = [yamlencode({
    replicaCount = 1 # demo sizing; HVD default is 3

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

    serviceAccount = {
      enabled = true
      name    = local.tfe_kube_svc_account
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.tfe_irsa_role_arn
      }
    }

    service = {
      type = "LoadBalancer"
      port = 443
      annotations = {
        # external-dns (addons layer) creates the Route 53 record for this
        "external-dns.alpha.kubernetes.io/hostname" = local.infra.tfe_fqdn

        # "external" + "ip" = current form of the deprecated "nlb-ip"
        "service.beta.kubernetes.io/aws-load-balancer-type"                 = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"               = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-subnets"              = join(",", local.infra.public_subnet_ids)
        "service.beta.kubernetes.io/aws-load-balancer-security-groups"      = local.infra.tfe_lb_security_group_id
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "https"
        # TFE v202505-1 serves /_health_check (the HVD template's newer path
        # 404s on this version) — revisit when bumping tfe_image_tag
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path" = "/_health_check"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port" = "8443"
      }
    }

    env = {
      secretRefs = [{ name = kubernetes_secret_v1.tfe_secrets.metadata[0].name }]

      variables = {
        TFE_HOSTNAME = local.infra.tfe_fqdn

        # Database (module defaults: database/user both "tfe")
        TFE_DATABASE_HOST       = local.infra.tfe_database_host
        TFE_DATABASE_NAME       = "tfe"
        TFE_DATABASE_USER       = "tfe"
        TFE_DATABASE_PARAMETERS = "sslmode=require"

        # Object storage (S3 via IRSA)
        TFE_OBJECT_STORAGE_TYPE                      = "s3"
        TFE_OBJECT_STORAGE_S3_BUCKET                 = local.infra.s3_bucket_name
        TFE_OBJECT_STORAGE_S3_REGION                 = data.aws_region.current.region
        TFE_OBJECT_STORAGE_S3_USE_INSTANCE_PROFILE   = true
        TFE_OBJECT_STORAGE_S3_SERVER_SIDE_ENCRYPTION = "AES256"

        # Redis (auth + TLS enabled by the module config)
        TFE_REDIS_HOST     = local.infra.redis_primary_endpoint
        TFE_REDIS_USE_AUTH = true
        TFE_REDIS_USE_TLS  = true
      }
    }
  })]
}
