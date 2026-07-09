# DNS per upi/aws/cloudformation/02_cluster_infra.yaml: public api record in
# the existing zone; a private hosted zone <cluster>.<base_domain> for api +
# api-int inside the VPC. (*.apps is created by the config layer after the
# ingress router's load balancer exists.)

# count-gated: the lookup fails hard when base_domain is the "unused" default
# (destroy without cluster.auto.tfvars.json), so skip it then — deletes use
# values recorded in state, not this expression.
data "aws_route53_zone" "base" {
  count        = var.base_domain != "unused" ? 1 : 0
  name         = var.base_domain
  private_zone = false
}

resource "aws_route53_record" "api_public" {
  zone_id = try(data.aws_route53_zone.base[0].zone_id, "unused")
  name    = "api.${local.cluster_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.api_ext.dns_name
    zone_id                = aws_lb.api_ext.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "cluster_private" {
  name = local.cluster_domain

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = local.cluster_tag
}

resource "aws_route53_record" "api_private" {
  for_each = toset(["api", "api-int"])

  zone_id = aws_route53_zone.cluster_private.zone_id
  name    = "${each.value}.${local.cluster_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.api_int.dns_name
    zone_id                = aws_lb.api_int.zone_id
    evaluate_target_health = false
  }
}
