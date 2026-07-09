# Node IAM roles per upi/aws/cloudformation/03_cluster_security.yaml +
# 04_cluster_bootstrap.yaml. The in-cluster cloud provider uses the master
# role for volumes/ELBs; workers only describe; bootstrap additionally reads
# its ignition from S3.

locals {
  node_assume = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  node_policies = {
    master = [
      "ec2:AttachVolume", "ec2:AuthorizeSecurityGroupIngress", "ec2:CreateSecurityGroup",
      "ec2:CreateTags", "ec2:CreateVolume", "ec2:DeleteSecurityGroup", "ec2:DeleteVolume",
      "ec2:Describe*", "ec2:DetachVolume", "ec2:ModifyInstanceAttribute", "ec2:ModifyVolume",
      "ec2:RevokeSecurityGroupIngress", "elasticloadbalancing:AddTags",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer", "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ConfigureHealthCheck", "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:CreateLoadBalancerPolicy", "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener", "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners", "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer", "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*", "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:ModifyListener", "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer", "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener", "kms:DescribeKey"
    ]
    worker    = ["ec2:DescribeInstances", "ec2:DescribeRegions"]
    bootstrap = ["ec2:Describe*", "ec2:AttachVolume", "ec2:DetachVolume"]
  }
}

resource "aws_iam_role" "node" {
  for_each = local.node_policies

  name               = "${var.infra_id}-${each.key}-role"
  assume_role_policy = local.node_assume
  tags               = local.cluster_tag
}

resource "aws_iam_role_policy" "node" {
  for_each = local.node_policies

  name = "${var.infra_id}-${each.key}-policy"
  role = aws_iam_role.node[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = each.value, Resource = "*" }]
  })
}

# Bootstrap reads bootstrap.ign from the bucket created by bootstrap.sh
resource "aws_iam_role_policy" "bootstrap_ign" {
  name = "${var.infra_id}-bootstrap-ign"
  role = aws_iam_role.node["bootstrap"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::${var.bootstrap_ign_bucket}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "node" {
  for_each = local.node_policies

  name = "${var.infra_id}-${each.key}-profile"
  role = aws_iam_role.node[each.key].name
}
