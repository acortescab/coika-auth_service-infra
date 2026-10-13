// Role assumed by the CD workflow of the application repository (not this one):
// the push-to-ecr job (from main) and the deploy job (environment "prod").
// It can push images to the ECR repository and log in to it; nothing else.
// The deploy itself runs over SSH and the instance pulls with its own instance profile.

locals {
  app_cd_role_name = "${local.ci_name_base}-cd-role${local.iam_name_suffix}"
}

data "aws_iam_policy_document" "app_cd_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_app_oidc_subjects
    }
  }
}

resource "aws_iam_role" "app_cd" {
  name                 = local.app_cd_role_name
  assume_role_policy   = data.aws_iam_policy_document.app_cd_assume_role.json
  permissions_boundary = aws_iam_policy.ci_boundary.arn
  max_session_duration = 3600

  tags = merge(
    {
      Name      = local.app_cd_role_name
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

data "aws_iam_policy_document" "app_cd" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "app_cd" {
  name   = "ecr-push"
  role   = aws_iam_role.app_cd.id
  policy = data.aws_iam_policy_document.app_cd.json
}
