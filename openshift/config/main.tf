# Layer 2: *.apps wildcard DNS. The ingress operator creates the router's LB
# but (UPI) nothing publishes DNS for it — these records point
# *.apps.<cluster_domain> at it. Applied mid-install by post-install.sh.

# try(): the cluster workspace may already be destroyed (outputs gone) and
# this layer must still plan its own destroy — deletes use state values.
locals {
  cluster_outputs = data.terraform_remote_state.cluster.outputs
  cluster = {
    base_domain_zone_id = try(local.cluster_outputs.base_domain_zone_id, "unused")
    private_zone_id     = try(local.cluster_outputs.private_zone_id, "unused")
    cluster_domain      = try(local.cluster_outputs.cluster_domain, "unused")
  }
}

resource "aws_route53_record" "apps_wildcard" {
  zone_id = local.cluster.base_domain_zone_id
  name    = "*.apps.${local.cluster.cluster_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [var.apps_lb_hostname]
}

# Same record in the private zone: in-cluster resolution uses the VPC
# resolver — without it the auth/console/canary operators stay degraded.
resource "aws_route53_record" "apps_wildcard_private" {
  zone_id = local.cluster.private_zone_id
  name    = "*.apps.${local.cluster.cluster_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [var.apps_lb_hostname]
}
