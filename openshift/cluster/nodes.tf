# RHCOS instances per upi/aws/cloudformation/04-06. Masters and workers get a
# tiny ignition "pointer" as user-data that fetches their real config from the
# Machine Config Server (api-int:22623, trusted via the ignition CA). The
# bootstrap node's full config is too large for user-data, so its pointer
# fetches bootstrap.ign from S3 using its instance profile.

locals {
  pointer_ignition = {
    for role in ["master", "worker"] : role => jsonencode({
      ignition = {
        version = "3.2.0"
        security = {
          tls = { certificateAuthorities = [{ source = var.ignition_ca }] }
        }
        config = {
          merge = [{ source = "https://api-int.${local.cluster_domain}:22623/config/${role}" }]
        }
      }
    })
  }

  bootstrap_ignition = jsonencode({
    ignition = {
      version = "3.2.0"
      config = {
        replace = { source = "s3://${var.bootstrap_ign_bucket}/bootstrap.ign" }
      }
    }
  })
}

resource "aws_instance" "bootstrap" {
  count = var.bootstrap_enabled ? 1 : 0

  ami                         = var.rhcos_ami
  instance_type               = "m6i.xlarge"
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.master.id, aws_security_group.bootstrap.id]
  iam_instance_profile        = aws_iam_instance_profile.node["bootstrap"].name
  user_data                   = local.bootstrap_ignition

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  tags = merge(local.cluster_tag, { Name = "${var.infra_id}-bootstrap" })
}

resource "aws_instance" "master" {
  count = 3

  ami                    = var.rhcos_ami
  instance_type          = var.master_instance_type
  subnet_id              = module.vpc.private_subnets[count.index]
  vpc_security_group_ids = [aws_security_group.master.id]
  iam_instance_profile   = aws_iam_instance_profile.node["master"].name
  user_data              = local.pointer_ignition["master"]

  # Operator pods assume their IAM roles via IMDS (identity.tf); the extra
  # network hop through the pod SDN needs a hop limit of 2 to reach it.
  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  tags = merge(
    { "kubernetes.io/cluster/${var.infra_id}" = "owned" },
    { Name = "${var.infra_id}-master-${count.index}" }
  )
}

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = var.rhcos_ami
  instance_type          = var.worker_instance_type
  subnet_id              = module.vpc.private_subnets[count.index % 3]
  vpc_security_group_ids = [aws_security_group.worker.id]
  iam_instance_profile   = aws_iam_instance_profile.node["worker"].name
  user_data              = local.pointer_ignition["worker"]

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  tags = merge(
    { "kubernetes.io/cluster/${var.infra_id}" = "owned" },
    { Name = "${var.infra_id}-worker-${count.index}" }
  )
}
