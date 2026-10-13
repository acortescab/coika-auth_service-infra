locals {
  // IAM is global: outside the primary region the names get a region suffix so
  // that a DR stack in the same account does not collide with the primary one.
  iam_name_suffix = var.aws_region == var.primary_region ? "" : "-${var.aws_region}"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name                 = "${var.instance_name}-role${local.iam_name_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume_role.json
  permissions_boundary = aws_iam_policy.ci_boundary.arn

  tags = merge(
    {
      Name      = "${var.instance_name}-role${local.iam_name_suffix}"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  count = var.enable_iam_instance_profile ? 1 : 0

  role       = aws_iam_role.ec2_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  count = var.enable_iam_instance_profile ? 1 : 0

  role       = aws_iam_role.ec2_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name = "${var.instance_name}-profile${local.iam_name_suffix}"
  role = aws_iam_role.ec2_role[0].name

  tags = merge(
    {
      Name      = "${var.instance_name}-profile${local.iam_name_suffix}"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

// The database host gets its own role (not the API one): SSM access plus write access to the snapshots bucket only.
resource "aws_iam_role" "db_role" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name                 = "${var.db_instance_name}-role${local.iam_name_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume_role.json
  permissions_boundary = aws_iam_policy.ci_boundary.arn

  tags = merge(
    {
      Name      = "${var.db_instance_name}-role${local.iam_name_suffix}"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_iam_role_policy_attachment" "db_ssm_core" {
  count = var.enable_iam_instance_profile ? 1 : 0

  role       = aws_iam_role.db_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "db_snapshots_access" {
  statement {
    sid       = "ListSnapshotsBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.db_snapshots.arn]
  }

  statement {
    sid       = "ReadWriteSnapshots"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.db_snapshots.arn}/*"]
  }
}

resource "aws_iam_role_policy" "db_snapshots_access" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name   = "db-snapshots-access"
  role   = aws_iam_role.db_role[0].id
  policy = data.aws_iam_policy_document.db_snapshots_access.json
}

resource "aws_iam_instance_profile" "db_profile" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name = "${var.instance_name}-db-profile${local.iam_name_suffix}"
  role = aws_iam_role.db_role[0].name

  tags = merge(
    {
      Name      = "${var.instance_name}-db-profile${local.iam_name_suffix}"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

// Secrets and app configuration live in SSM Parameter Store (SecureString), created outside
// Terraform so their values never reach the state or user_data. The instances read them at
// runtime with their role. Layout:
//   <prefix>/db/*   PostgreSQL user, password, database name (read by both hosts) and, created by
//                   Terraform, DB_HOST / DB_PORT
//   <prefix>/app/*  API environment variables (read by the API host only)
locals {
  ssm_prefix   = coalesce(var.ssm_parameter_prefix, "/${var.project_name}/${var.environment}")
  ssm_arn_base = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}"
}

// Where the database listens. Not a secret, so Terraform owns it (it follows the instance if it is
// ever replaced); the API host combines it with db/POSTGRES_* to build its DATABASE_URL_* at deploy time.
resource "aws_ssm_parameter" "db_host" {
  name  = "${local.ssm_prefix}/db/DB_HOST"
  type  = "String"
  value = aws_instance.database.private_ip

  tags = merge(
    {
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_ssm_parameter" "db_port" {
  name  = "${local.ssm_prefix}/db/DB_PORT"
  type  = "String"
  value = tostring(var.db_port)

  tags = merge(
    {
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

data "aws_iam_policy_document" "ssm_read_db" {
  statement {
    sid     = "ReadDbParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "${local.ssm_arn_base}/db",
      "${local.ssm_arn_base}/db/*",
    ]
  }
}

data "aws_iam_policy_document" "ssm_read_api" {
  source_policy_documents = [data.aws_iam_policy_document.ssm_read_db.json]

  statement {
    sid     = "ReadAppParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "${local.ssm_arn_base}/app",
      "${local.ssm_arn_base}/app/*",
    ]
  }
}

resource "aws_iam_role_policy" "api_ssm_parameters" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name   = "ssm-parameters-read"
  role   = aws_iam_role.ec2_role[0].id
  policy = data.aws_iam_policy_document.ssm_read_api.json
}

resource "aws_iam_role_policy" "db_ssm_parameters" {
  count = var.enable_iam_instance_profile ? 1 : 0

  name   = "ssm-parameters-read"
  role   = aws_iam_role.db_role[0].id
  policy = data.aws_iam_policy_document.ssm_read_db.json
}
