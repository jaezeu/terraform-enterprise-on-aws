# imds-proxy — makes EC2 instance-metadata credentials reachable from pods.
# OVN-Kubernetes blocks pod-network access to IMDS (Red Hat solution 4498111)
# and the SCP rules out OIDC/IRSA, so this hostNetwork socat DaemonSet relays
# TCP to IMDS and the Service gives pods a stable endpoint. TFE's AWS SDK is
# pointed at it via AWS_EC2_METADATA_SERVICE_ENDPOINT and picks up worker-
# node-role credentials (short-lived STS; scoped in backing.tf). Trade-off:
# any pod that can reach the Service gets node-role credentials — per-node
# isolation, demo-appropriate.

locals {
  imds_proxy_port = 25169 # arbitrary high port, unused on the host
}

resource "kubernetes_service_account_v1" "imds_proxy" {
  metadata {
    name      = "imds-proxy"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  # OpenShift auto-attaches the SA's dockercfg pull secret (+ an annotation)
  lifecycle {
    ignore_changes = [image_pull_secret, secret, metadata[0].annotations]
  }
}

# hostNetwork needs the hostnetwork-v2 SCC; OpenShift ships a ClusterRole per
# SCC for exactly this kind of grant.
resource "kubernetes_role_binding_v1" "imds_proxy_scc" {
  metadata {
    name      = "imds-proxy-scc-hostnetwork"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:openshift:scc:hostnetwork-v2"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.imds_proxy.metadata[0].name
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }
}

resource "kubernetes_daemon_set_v1" "imds_proxy" {
  metadata {
    name      = "imds-proxy"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  spec {
    selector {
      match_labels = { app = "imds-proxy" }
    }

    template {
      metadata {
        labels = { app = "imds-proxy" }
      }

      spec {
        host_network         = true
        service_account_name = kubernetes_service_account_v1.imds_proxy.metadata[0].name

        container {
          name  = "socat"
          image = "docker.io/alpine/socat:1.8.0.0"
          args  = ["TCP-LISTEN:${local.imds_proxy_port},fork,reuseaddr", "TCP:169.254.169.254:80"]

          port {
            container_port = local.imds_proxy_port
            host_port      = local.imds_proxy_port
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "imds_proxy" {
  metadata {
    name      = "imds-proxy"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  spec {
    selector = { app = "imds-proxy" }

    port {
      port        = 80
      target_port = local.imds_proxy_port
    }
  }
}
