// Roles assumed by GitHub Actions through OIDC. Two roles on purpose:
//  - plan:  read-only, assumable from pull requests and branches
//  - apply: can change the infrastructure, assumable only from the "production" environment
//
// Every role created by this stack carries the permissions boundary below, which caps
// what it can ever do. The apply role cannot edit the boundary, remove it from a role,
// or create a role without it, so it cannot escalate beyond the boundary.
//
// Bootstrap: the boundary and the roles are created by the first apply, which must run
// with other credentials (for example the legacy deploy role or a local admin profile).
// Later changes to the boundary policy must also be applied with admin credentials.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  ci_account_id = data.aws_caller_identity.current.account_id
  ci_name_base  = var.project_name

  // Built from the name (not from the resource) so the boundary can refer to itself.
  ci_boundary_name = "${local.ci_name_base}-ci-boundary${local.iam_name_suffix}"
  ci_boundary_arn  = "arn:aws:iam::${local.ci_account_id}:policy/${local.ci_boundary_name}"

  ci_trust_subjects = {
    plan  = ["${var.github_oidc_subject_prefix}:environment:${var.github_plan_environment}"]
    apply = ["${var.github_oidc_subject_prefix}:environment:${var.github_apply_environment}"]
  }
}

data "aws_iam_policy_document" "ci_assume_role" {
  for_each = local.ci_trust_subjects

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
      values   = each.value
    }
  }
}

// What the apply role is allowed to do. It is also the core of the boundary.
data "aws_iam_policy_document" "ci_apply_core" {
  statement {
    sid       = "TerraformState"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket_name}"]
  }

  statement {
    sid     = "TerraformStateObjects"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket_name}/terraform.tfstate",
      "arn:aws:s3:::${var.tfstate_bucket_name}/regions/*/terraform.tfstate",
    ]
  }

  statement {
    sid = "Ec2"
    actions = [
      "ec2:Describe*",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyInstanceMetadataOptions",
      "ec2:ModifyInstanceCreditSpecification",
      "ec2:MonitorInstances",
      "ec2:UnmonitorInstances",
      "ec2:ModifyVolume",
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:AssociateIamInstanceProfile",
      "ec2:ReplaceIamInstanceProfileAssociation",
      "ec2:DisassociateIamInstanceProfile",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:ImportKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.ci_allowed_regions
    }
  }

  statement {
    sid = "IamRolesAndProfiles"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListInstanceProfilesForRole",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
      "iam:ListInstanceProfileTags",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${local.ci_account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${local.ci_account_id}:instance-profile/${var.instance_name}-*",
    ]
  }

  // Roles can only be created (or have their boundary changed) with the boundary attached.
  statement {
    sid       = "IamCreateRoleWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["arn:aws:iam::${local.ci_account_id}:role/${var.project_name}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.ci_boundary_arn]
    }
  }

  statement {
    sid       = "IamManagedPolicyAttachments"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:aws:iam::${local.ci_account_id}:role/${var.project_name}-*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      ]
    }
  }

  statement {
    sid = "DbSnapshotsBucket"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucket*",
      "s3:PutBucket*",
      "s3:DeleteBucketPolicy",
      "s3:Get*Configuration",
      "s3:Put*Configuration",
    ]
    resources = [
      "arn:aws:s3:::${local.db_snapshots_bucket_name}",
      "arn:aws:s3:::${local.db_snapshots_replica_bucket_name}",
    ]
  }

  statement {
    sid       = "IamPassRoleToEc2AndS3"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.ci_account_id}:role/${var.project_name}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "s3.amazonaws.com"]
    }
  }

  statement {
    sid       = "IamReadBoundaryAndOidcProvider"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  statement {
    sid = "EcrRepository"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:GetRepositoryPolicy",
      "ecr:GetLifecyclePolicy",
    ]
    resources = ["arn:aws:ecr:*:${local.ci_account_id}:repository/${split("/", var.ecr_repository_name)[0]}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.ci_allowed_regions
    }
  }

  statement {
    sid       = "EcrRegistry"
    actions   = ["ecr:DescribeRegistry", "ecr:PutReplicationConfiguration", "ecr:DescribeRepositories"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.ci_allowed_regions
    }
  }

  statement {
    sid       = "EcrReplicationServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.ci_account_id}:role/aws-service-role/replication.ecr.amazonaws.com/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["replication.ecr.amazonaws.com"]
    }
  }
}

// The cap: the apply permissions, plus what the other roles created here need
// (the plan policy, SSM and ECR pull for the instance role), plus guard rails.
data "aws_iam_policy_document" "ci_boundary" {
  source_policy_documents = [data.aws_iam_policy_document.ci_apply_core.json]

  statement {
    sid       = "InstanceRuntime"
    actions   = ["ssm:*", "ssmmessages:*", "ec2messages:*", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
    resources = ["*"]
  }

  statement {
    sid       = "DbSnapshotsRuntime"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.db_snapshots_bucket_name}", "arn:aws:s3:::${local.db_snapshots_bucket_name}/*"]
  }

  statement {
    sid = "DbSnapshotsReplication"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
      "s3:ListBucket",
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = [
      "arn:aws:s3:::${local.db_snapshots_bucket_name}",
      "arn:aws:s3:::${local.db_snapshots_bucket_name}/*",
      "arn:aws:s3:::${local.db_snapshots_replica_bucket_name}",
      "arn:aws:s3:::${local.db_snapshots_replica_bucket_name}/*",
    ]
  }

  statement {
    sid = "AppCiEcrPush"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRoleWithoutBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.ci_boundary_arn]
    }
  }

  statement {
    sid       = "DenyRemoveBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyEditBoundary"
    effect = "Deny"
    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.ci_boundary_arn]
  }
}

resource "aws_iam_policy" "ci_boundary" {
  name        = local.ci_boundary_name
  description = "Permissions boundary for the roles created by Terraform for ${var.project_name}"
  policy      = data.aws_iam_policy_document.ci_boundary.json

  tags = merge(
    {
      Name        = local.ci_boundary_name
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

resource "aws_iam_role" "ci" {
  for_each = local.ci_trust_subjects

  name                 = "${local.ci_name_base}-infra-ci_${each.key}-role${local.iam_name_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.ci_assume_role[each.key].json
  permissions_boundary = aws_iam_policy.ci_boundary.arn
  max_session_duration = 3600

  tags = merge(
    {
      Name        = "${local.ci_name_base}-infra-ci_${each.key}-role${local.iam_name_suffix}"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

// Plan: read-only, limited to the resources this stack manages.
data "aws_iam_policy_document" "ci_plan" {
  statement {
    sid       = "TerraformStateRead"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket_name}"]
  }

  statement {
    sid     = "TerraformStateObjectsRead"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket_name}/terraform.tfstate",
      "arn:aws:s3:::${var.tfstate_bucket_name}/regions/*/terraform.tfstate",
    ]
  }

  statement {
    sid       = "Ec2Read"
    actions   = ["ec2:Describe*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.ci_allowed_regions
    }
  }

  statement {
    sid = "IamRead"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListRoleTags",
      "iam:ListInstanceProfilesForRole",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfileTags",
    ]
    resources = [
      "arn:aws:iam::${local.ci_account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${local.ci_account_id}:instance-profile/${var.instance_name}-*",
    ]
  }

  statement {
    sid       = "IamReadBoundaryAndOidcProviderPlan"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  statement {
    sid     = "DbSnapshotsBucketRead"
    actions = ["s3:ListBucket", "s3:GetBucket*", "s3:Get*Configuration"]
    resources = [
      "arn:aws:s3:::${local.db_snapshots_bucket_name}",
      "arn:aws:s3:::${local.db_snapshots_replica_bucket_name}",
    ]
  }

  statement {
    sid = "EcrRead"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:DescribeRegistry",
      "ecr:ListTagsForResource",
      "ecr:GetRepositoryPolicy",
      "ecr:GetLifecyclePolicy",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.ci_allowed_regions
    }
  }
}

resource "aws_iam_role_policy" "ci_plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.ci["plan"].id
  policy = data.aws_iam_policy_document.ci_plan.json
}
// Apply: only what this stack manages (the boundary caps it even if this policy is edited).
resource "aws_iam_role_policy" "ci_apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.ci["apply"].id
  policy = data.aws_iam_policy_document.ci_apply_core.json
}
