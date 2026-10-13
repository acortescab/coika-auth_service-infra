terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0, < 6.65.0"
    }
  }

  // Remote state in S3 with native locking (use_lockfile, no DynamoDB table).
  // The bucket is not in the code (backend blocks cannot use variables); pass it at init:
  //   terraform init -backend-config="bucket=<bucket>"
  // The state bucket is created by hand and is outside this stack.
  backend "s3" {
    key          = "terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
