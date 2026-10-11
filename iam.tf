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
