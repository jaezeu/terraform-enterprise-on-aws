# API load balancers per upi/aws/cloudformation/02_cluster_infra.yaml:
# external NLB (api: 6443) + internal NLB (api: 6443, machine-config: 22623).

resource "aws_lb" "api_ext" {
  name               = "${var.infra_id}-ext"
  load_balancer_type = "network"
  internal           = false
  subnets            = module.vpc.public_subnets
  tags               = local.cluster_tag
}

resource "aws_lb" "api_int" {
  name               = "${var.infra_id}-int"
  load_balancer_type = "network"
  internal           = true
  subnets            = module.vpc.private_subnets
  tags               = local.cluster_tag
}

locals {
  target_groups = {
    ext_api = { lb = "ext", port = 6443, hc_path = "/readyz" }
    int_api = { lb = "int", port = 6443, hc_path = "/readyz" }
    int_mcs = { lb = "int", port = 22623, hc_path = "/healthz" }
  }
}

resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  name        = "${var.infra_id}-${replace(each.key, "_", "-")}"
  vpc_id      = module.vpc.vpc_id
  port        = each.value.port
  protocol    = "TCP"
  target_type = "instance"

  health_check {
    protocol            = "HTTPS"
    path                = each.value.hc_path
    port                = tostring(each.value.port)
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.cluster_tag
}

resource "aws_lb_listener" "this" {
  for_each = local.target_groups

  load_balancer_arn = each.value.lb == "ext" ? aws_lb.api_ext.arn : aws_lb.api_int.arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}

# Masters serve both API target groups and the MCS; the bootstrap node joins
# all three until bootstrap_enabled is flipped off.
locals {
  master_tg_attachments = {
    for pair in setproduct(keys(local.target_groups), range(3)) :
    "${pair[0]}-${pair[1]}" => { tg = pair[0], index = pair[1] }
  }
}

resource "aws_lb_target_group_attachment" "master" {
  for_each = local.master_tg_attachments

  target_group_arn = aws_lb_target_group.this[each.value.tg].arn
  target_id        = aws_instance.master[each.value.index].id
}

resource "aws_lb_target_group_attachment" "bootstrap" {
  for_each = var.bootstrap_enabled ? local.target_groups : {}

  target_group_arn = aws_lb_target_group.this[each.key].arn
  target_id        = aws_instance.bootstrap[0].id
}
