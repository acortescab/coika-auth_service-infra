terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0, < 6.65.0"
    }
  }

  // Remote state is stored in S3 so the stack can be shared safely.
  backend "s3" {
    bucket  = "coika-auth-tfstate-s3-290294660813-eu-west-1-an"
    key     = "terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}