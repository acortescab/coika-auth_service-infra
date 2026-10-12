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
      Name        = local.db_snapshots_bucket_name
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
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
