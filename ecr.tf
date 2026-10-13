// ECR repository for the application image.

data "aws_caller_identity" "current" {}

# Registry-level setting: replicates images pushed after it is enabled (existing images are not copied).
# ECR creates the destination repository on its own, so in a DR region import it instead of creating it.
resource "aws_ecr_replication_configuration" "app" {
  count = length(var.ecr_replication_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = toset(var.ecr_replication_regions)

        content {
          region      = destination.value
          registry_id = data.aws_caller_identity.current.account_id
        }
      }

      repository_filter {
        filter      = split("/", var.ecr_repository_name)[0]
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    {
      Name      = var.ecr_repository_name
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}
