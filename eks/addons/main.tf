# Layer 2: cluster addons — AWS Load Balancer Controller and external-dns.
# Applied after infra; both use IRSA roles created by the infra layer.

# local.infra: see data.tf

# Provisions the NLB when the TFE Service (tfe layer) is created.
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName = local.infra.eks_cluster_name
    region      = data.aws_region.current.region
    vpcId       = local.infra.vpc_id
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.aws_lb_controller_irsa_role_arn
      }
    }
  })]
}

# Manages Route 53 records from Services' hostname annotations — replaces a
# Terraform DNS record and keeps it correct if the NLB is ever recreated.
resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [yamlencode({
    provider = { name = "aws" }
    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.infra.external_dns_irsa_role_arn
      }
    }
    # sync (not upsert-only) so records are cleaned up when Services are deleted.
    policy        = "sync"
    txtOwnerId    = local.infra.eks_cluster_name
    domainFilters = [local.infra.route53_zone_name]
    env = [{
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.region
    }]
  })]
}
