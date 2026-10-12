// Provider configuration for AWS resources.
provider "aws" {
  region = var.aws_region
}

// Destination region of the database snapshots replication. Without replication it points
// at the main region and no resources use it.
provider "aws" {
  alias  = "replica"
  region = coalesce(var.db_snapshots_replication_region, var.aws_region)
}
