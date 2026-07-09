# No external-dns here — Terraform reads the ELB hostname off the Service and
# creates the record itself. depends_on defers the read to apply time (needed
# on day-0 when the Service doesn't exist yet), so plans always show this
# record as "(known after apply)" — plan noise, not drift.

data "kubernetes_service_v1" "tfe" {
  metadata {
    name      = "terraform-enterprise"
    namespace = kubernetes_namespace_v1.tfe.metadata[0].name
  }

  depends_on = [helm_release.terraform_enterprise]
}

resource "aws_route53_record" "tfe" {
  zone_id = local.cluster.base_domain_zone_id
  name    = local.tfe_fqdn
  type    = "CNAME"
  ttl     = 300
  records = [data.kubernetes_service_v1.tfe.status[0].load_balancer[0].ingress[0].hostname]
}
