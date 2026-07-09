# =============================================================================
# TFE's external services: PostgreSQL (RDS), Redis (ElastiCache), S3.
# Demo sizing throughout; ingress is scoped to the cluster VPC.
# =============================================================================

locals {
  infra_id = local.cluster.infra_id # local.cluster: see data.tf
  tfe_fqdn = "${var.tfe_hostname_label}.${local.cluster.base_domain}"
}

# --- PostgreSQL ---------------------------------------------------------------
resource "aws_db_subnet_group" "tfe" {
  name       = "${local.infra_id}-tfe"
  subnet_ids = local.cluster.private_subnet_ids
}

resource "aws_security_group" "postgres" {
  name   = "${local.infra_id}-tfe-postgres"
  vpc_id = local.cluster.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.cluster.vpc_cidr]
  }
}

resource "aws_db_instance" "tfe" {
  identifier     = "${local.infra_id}-tfe"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.medium"

  allocated_storage = 50
  storage_type      = "gp3"

  db_name  = "tfe"
  username = "tfe"
  password = data.aws_secretsmanager_secret_version.tfe["database_password"].secret_string

  db_subnet_group_name   = aws_db_subnet_group.tfe.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  skip_final_snapshot = true # demo — recreated from scratch with the cluster
}

# --- Redis --------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "tfe" {
  name       = "${local.infra_id}-tfe"
  subnet_ids = local.cluster.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name   = "${local.infra_id}-tfe-redis"
  vpc_id = local.cluster.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [local.cluster.vpc_cidr]
  }
}

resource "aws_elasticache_replication_group" "tfe" {
  replication_group_id = "${local.infra_id}-tfe"
  description          = "TFE Redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.small"
  num_cache_clusters   = 1

  # TFE_REDIS_USE_AUTH/USE_TLS in the chart values match this pair.
  transit_encryption_enabled = true
  auth_token                 = data.aws_secretsmanager_secret_version.tfe["redis_password"].secret_string

  subnet_group_name  = aws_elasticache_subnet_group.tfe.name
  security_group_ids = [aws_security_group.redis.id]
}

# --- S3 (TFE object storage) ---------------------------------------------------
resource "aws_s3_bucket" "tfe" {
  bucket        = "${local.infra_id}-tfe-app"
  force_destroy = true # demo — allow destroy with objects present
}

# TFE reaches S3 with the WORKER NODE ROLE (via the imds-proxy), so the
# bucket grant goes on the node role — per-node isolation, see imds-proxy.tf.
resource "aws_iam_role_policy" "worker_tfe_s3" {
  name = "${local.infra_id}-worker-tfe-s3"
  role = local.cluster.worker_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.tfe.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tfe.arn}/*"
      }
    ]
  })
}
