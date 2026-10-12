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
      Name        = "${var.instance_name}-role${local.iam_name_suffix}"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
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
      Name        = "${var.instance_name}-profile${local.iam_name_suffix}"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
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
      Name        = "${var.db_instance_name}-role${local.iam_name_suffix}"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
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
      Name        = "${var.instance_name}-db-profile${local.iam_name_suffix}"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}
