# Cloud-credential identity (credentialsMode: Manual) WITHOUT an OIDC
# provider — the sandbox SCP denies self-hosted issuers. Each operator's
# credential secret instead uses AWS shared-config role chaining
# (role_arn + credential_source = Ec2InstanceMetadata): the operator assumes
# its role FROM the node's instance-profile role via IMDS. Short-lived STS
# only; trade-off is per-node (not per-pod) isolation.
#
# bootstrap.sh runs `ccoctl aws create-all --dry-run` and we consume only the
# emitted permission policies (06-*); the OIDC trust policies are replaced.

locals {
  cco_dir = "${path.module}/ccoctl-generated"

  # 05-N-<role-name>-role.json names the role; 06-N-<role-name>-policy.json
  # holds its permissions. ccoctl truncates IAM role names to 64 chars in its
  # credential manifests — match it so the ARNs bootstrap.sh fills in resolve.
  cco_roles = {
    for f in fileset(local.cco_dir, "05-*-role.json") :
    substr(regex("^05-\\d+-(.+)-role\\.json$", f)[0], 0, 64) => try(
      jsondecode(file("${local.cco_dir}/${replace(replace(f, "05-", "06-"), "-role.json", "-policy.json")}")).PolicyDocument,
      file("${local.cco_dir}/${replace(replace(f, "05-", "06-"), "-role.json", "-policy.json")}")
    )
  }

  # Operator pods land on both control-plane and worker nodes (registry, CSI,
  # ingress), so both node roles must be able to assume the operator roles.
  cco_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [aws_iam_role.node["master"].arn, aws_iam_role.node["worker"].arn]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "cco" {
  for_each = local.cco_roles

  name               = each.key
  assume_role_policy = local.cco_trust
  tags               = local.cluster_tag
}

resource "aws_iam_role_policy" "cco" {
  for_each = local.cco_roles

  name   = each.key
  role   = aws_iam_role.cco[each.key].id
  policy = each.value
}

# The other half of the chain: node roles may assume the operator roles.
resource "aws_iam_role_policy" "node_assume_cco" {
  for_each = toset(["master", "worker"])

  name = "${var.infra_id}-${each.key}-assume-cco"
  role = aws_iam_role.node[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [for r in aws_iam_role.cco : r.arn]
    }]
  })
}
