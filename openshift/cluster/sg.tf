# Security groups per upi/aws/cloudformation/03_cluster_security.yaml.
# The kubernetes.io/cluster tag lets the in-cluster AWS cloud provider manage
# additional rules (e.g. for the router's ELB) on these groups.

locals {
  # port/proto matrix shared between control plane and workers
  node_shared_rules = {
    vxlan        = { protocol = "udp", from = 4789, to = 4789 }
    geneve       = { protocol = "udp", from = 6081, to = 6081 }
    ike          = { protocol = "udp", from = 500, to = 500 }
    ike_nat_t    = { protocol = "udp", from = 4500, to = 4500 }
    esp          = { protocol = "50", from = 0, to = 0 }
    internal_tcp = { protocol = "tcp", from = 9000, to = 9999 }
    internal_udp = { protocol = "udp", from = 9000, to = 9999 }
    nodeport_tcp = { protocol = "tcp", from = 30000, to = 32767 }
    nodeport_udp = { protocol = "udp", from = 30000, to = 32767 }
  }
}

resource "aws_security_group" "master" {
  name   = "${var.infra_id}-master-sg"
  vpc_id = module.vpc.vpc_id
  tags   = merge(local.cluster_tag, { Name = "${var.infra_id}-master-sg" })
}

resource "aws_security_group" "worker" {
  name   = "${var.infra_id}-worker-sg"
  vpc_id = module.vpc.vpc_id
  tags   = merge(local.cluster_tag, { Name = "${var.infra_id}-worker-sg" })
}

# --- master: control-plane-only ports ---------------------------------------
resource "aws_security_group_rule" "master_api" {
  security_group_id = aws_security_group.master.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_blocks       = var.api_ingress_cidrs
  description       = "Kubernetes API (NLB preserves client IPs)"
}

resource "aws_security_group_rule" "master_mcs" {
  security_group_id = aws_security_group.master.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22623
  to_port           = 22623
  cidr_blocks       = [var.vpc_cidr]
  description       = "Machine Config Server (in-VPC only)"
}

resource "aws_security_group_rule" "master_etcd" {
  security_group_id        = aws_security_group.master.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 2379
  to_port                  = 2380
  source_security_group_id = aws_security_group.master.id
  description              = "etcd"
}

resource "aws_security_group_rule" "master_kubelet_range" {
  for_each = { master = aws_security_group.master.id, worker = aws_security_group.worker.id }

  security_group_id        = aws_security_group.master.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 10250
  to_port                  = 10259
  source_security_group_id = each.value
  description              = "kubelet, scheduler, controller-manager (${each.key})"
}

# --- worker: kubelet ----------------------------------------------------------
resource "aws_security_group_rule" "worker_kubelet" {
  for_each = { master = aws_security_group.master.id, worker = aws_security_group.worker.id }

  security_group_id        = aws_security_group.worker.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 10250
  to_port                  = 10250
  source_security_group_id = each.value
  description              = "kubelet (${each.key})"
}

# --- shared matrix applied to both groups from both groups -------------------
resource "aws_security_group_rule" "shared" {
  for_each = {
    for pair in setproduct(["master", "worker"], ["master", "worker"], keys(local.node_shared_rules)) :
    "${pair[0]}-${pair[1]}-${pair[2]}" => {
      target = pair[0]
      source = pair[1]
      rule   = local.node_shared_rules[pair[2]]
      desc   = pair[2]
    }
  }

  security_group_id        = each.value.target == "master" ? aws_security_group.master.id : aws_security_group.worker.id
  type                     = "ingress"
  protocol                 = each.value.rule.protocol
  from_port                = each.value.rule.from
  to_port                  = each.value.rule.to
  source_security_group_id = each.value.source == "master" ? aws_security_group.master.id : aws_security_group.worker.id
  description              = "${each.value.desc} (${each.value.source})"
}

# --- in-VPC ssh/icmp on both, all egress --------------------------------------
resource "aws_security_group_rule" "vpc_basics" {
  for_each = {
    master-icmp = { sg = aws_security_group.master.id, proto = "icmp", from = -1, to = -1 }
    master-ssh  = { sg = aws_security_group.master.id, proto = "tcp", from = 22, to = 22 }
    worker-icmp = { sg = aws_security_group.worker.id, proto = "icmp", from = -1, to = -1 }
    worker-ssh  = { sg = aws_security_group.worker.id, proto = "tcp", from = 22, to = 22 }
  }

  security_group_id = each.value.sg
  type              = "ingress"
  protocol          = each.value.proto
  from_port         = each.value.from
  to_port           = each.value.to
  cidr_blocks       = [var.vpc_cidr]
  description       = "in-VPC ${each.key}"
}

# Bootstrap-only debug access (per 04_cluster_bootstrap.yaml): SSH + the
# journald gateway for watching bootstrap progress from outside the VPC.
resource "aws_security_group" "bootstrap" {
  name   = "${var.infra_id}-bootstrap-sg"
  vpc_id = module.vpc.vpc_id
  tags   = merge(local.cluster_tag, { Name = "${var.infra_id}-bootstrap-sg" })
}

resource "aws_security_group_rule" "bootstrap_debug" {
  for_each = { ssh = 22, journald = 19531 }

  security_group_id = aws_security_group.bootstrap.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_blocks       = var.api_ingress_cidrs
  description       = "bootstrap ${each.key}"
}

resource "aws_security_group_rule" "egress_all" {
  for_each = {
    master    = aws_security_group.master.id
    worker    = aws_security_group.worker.id
    bootstrap = aws_security_group.bootstrap.id
  }

  security_group_id = each.value
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "all egress"
}
