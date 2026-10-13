// Bucket for the database snapshots/dumps. Private, encrypted, versioned, TLS-only.
// The database host writes to it through its instance role (see iam.tf), no static credentials.

locals {
  // S3 bucket names cannot contain underscores, and must be globally unique.
  db_snapshots_bucket_name = "${replace(var.project_name, "_", "-")}-db-snapshots-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "db_snapshots" {
  bucket        = local.db_snapshots_bucket_name
  force_destroy = true

  tags = merge(
    {
      Name      = local.db_snapshots_bucket_name
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_s3_bucket_public_access_block" "db_snapshots" {
  bucket = aws_s3_bucket.db_snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "db_snapshots" {
  bucket = aws_s3_bucket.db_snapshots.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "db_snapshots" {
  bucket = aws_s3_bucket.db_snapshots.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "db_snapshots" {
  bucket = aws_s3_bucket.db_snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "db_snapshots" {
  bucket = aws_s3_bucket.db_snapshots.id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = var.db_snapshots_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.db_snapshots_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.db_snapshots]
}

data "aws_iam_policy_document" "db_snapshots_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.db_snapshots.arn, "${aws_s3_bucket.db_snapshots.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "db_snapshots" {
  bucket = aws_s3_bucket.db_snapshots.id
  policy = data.aws_iam_policy_document.db_snapshots_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.db_snapshots]
}

// ---------------------------------------------------------------------------
// Cross-region replication to the DR region (only from the primary region).
// The replica uses the name the DR stack would give its own bucket, so after a failover
// the DR stack adopts it (terraform import) and the DR database host reads from it.
// ---------------------------------------------------------------------------

locals {
  db_snapshots_replication_enabled = var.aws_region == var.primary_region && coalesce(var.db_snapshots_replication_region, "none") != "none"
  db_snapshots_replica_bucket_name = "${replace(var.project_name, "_", "-")}-db-snapshots-${data.aws_caller_identity.current.account_id}-${coalesce(var.db_snapshots_replication_region, var.aws_region)}"
}

resource "aws_s3_bucket" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket        = local.db_snapshots_replica_bucket_name
  force_destroy = true

  tags = merge(
    {
      Name      = local.db_snapshots_replica_bucket_name
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_s3_bucket_public_access_block" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket = aws_s3_bucket.db_snapshots_replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket = aws_s3_bucket.db_snapshots_replica[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket = aws_s3_bucket.db_snapshots_replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket = aws_s3_bucket.db_snapshots_replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket = aws_s3_bucket.db_snapshots_replica[0].id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = var.db_snapshots_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.db_snapshots_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.db_snapshots_replica]
}

data "aws_iam_policy_document" "db_snapshots_replica_bucket" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.db_snapshots_replica[0].arn, "${aws_s3_bucket.db_snapshots_replica[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  bucket = aws_s3_bucket.db_snapshots_replica[0].id
  policy = data.aws_iam_policy_document.db_snapshots_replica_bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.db_snapshots_replica]
}

// Role S3 assumes to copy objects from the source to the replica bucket.
data "aws_iam_policy_document" "s3_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_snapshots_replication" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  name                 = "${var.project_name}-db-snapshots-replication-role${local.iam_name_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.s3_assume_role.json
  permissions_boundary = aws_iam_policy.ci_boundary.arn

  tags = merge(
    {
      Name      = "${var.project_name}-db-snapshots-replication-role${local.iam_name_suffix}"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

data "aws_iam_policy_document" "db_snapshots_replication" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  statement {
    sid       = "ReadReplicationConfig"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.db_snapshots.arn]
  }

  statement {
    sid       = "ReadSourceObjects"
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${aws_s3_bucket.db_snapshots.arn}/*"]
  }

  statement {
    sid       = "WriteReplicaObjects"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.db_snapshots_replica[0].arn}/*"]
  }
}

resource "aws_iam_role_policy" "db_snapshots_replication" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  name   = "db-snapshots-replication"
  role   = aws_iam_role.db_snapshots_replication[0].id
  policy = data.aws_iam_policy_document.db_snapshots_replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "db_snapshots" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  role   = aws_iam_role.db_snapshots_replication[0].arn
  bucket = aws_s3_bucket.db_snapshots.id

  rule {
    id       = "replicate-to-dr"
    status   = "Enabled"
    priority = 0

    filter {}

    # Deleting or expiring a snapshot in the primary region must not remove the DR copy.
    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket = aws_s3_bucket.db_snapshots_replica[0].arn
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.db_snapshots,
    aws_s3_bucket_versioning.db_snapshots_replica,
    aws_iam_role_policy.db_snapshots_replication,
  ]
}

// ---------------------------------------------------------------------------
// Reverse direction (DR -> primary), so snapshots uploaded to the DR bucket during a failover
// come back to the primary region. S3 does not re-replicate objects that are themselves
// replicas, so the two rules do not loop.
// ---------------------------------------------------------------------------

resource "aws_iam_role" "db_snapshots_replication_reverse" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  name                 = "${var.project_name}-db-snapshots-replication-reverse-role${local.iam_name_suffix}"
  assume_role_policy   = data.aws_iam_policy_document.s3_assume_role.json
  permissions_boundary = aws_iam_policy.ci_boundary.arn

  tags = merge(
    {
      Name      = "${var.project_name}-db-snapshots-replication-reverse-role${local.iam_name_suffix}"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

data "aws_iam_policy_document" "db_snapshots_replication_reverse" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  statement {
    sid       = "ReadReplicationConfig"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.db_snapshots_replica[0].arn]
  }

  statement {
    sid       = "ReadSourceObjects"
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${aws_s3_bucket.db_snapshots_replica[0].arn}/*"]
  }

  statement {
    sid       = "WriteDestinationObjects"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.db_snapshots.arn}/*"]
  }
}

resource "aws_iam_role_policy" "db_snapshots_replication_reverse" {
  count = local.db_snapshots_replication_enabled ? 1 : 0

  name   = "db-snapshots-replication-reverse"
  role   = aws_iam_role.db_snapshots_replication_reverse[0].id
  policy = data.aws_iam_policy_document.db_snapshots_replication_reverse[0].json
}

resource "aws_s3_bucket_replication_configuration" "db_snapshots_replica" {
  count    = local.db_snapshots_replication_enabled ? 1 : 0
  provider = aws.replica

  role   = aws_iam_role.db_snapshots_replication_reverse[0].arn
  bucket = aws_s3_bucket.db_snapshots_replica[0].id

  rule {
    id       = "replicate-to-primary"
    status   = "Enabled"
    priority = 0

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket = aws_s3_bucket.db_snapshots.arn
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.db_snapshots,
    aws_s3_bucket_versioning.db_snapshots_replica,
    aws_iam_role_policy.db_snapshots_replication_reverse,
  ]
}
