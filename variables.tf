// Input variables for region, networking, and compute settings.
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "coika-auth_service-instance"
}

variable "environment" {
  description = "Environment tag value (for example: dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project tag value"
  type        = string
  default     = "coika-auth_service"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "availability_zone" {
  description = "Optional availability zone for the instance (for example: eu-west-1a)"
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Optional subnet ID. If null, the first default VPC subnet is used"
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "Whether to associate a public IP to the instance"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access"
  type        = string
  default     = "coika-auth_service-kp"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to access SSH port 22"
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_ingress_cidrs" {
  description = "CIDR blocks allowed to reach application ports"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30
}

variable "root_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "ami_architecture" {
  description = "Architecture for Ubuntu AMI lookup (x86_64 or arm64)"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.ami_architecture)
    error_message = "ami_architecture must be x86_64 or arm64."
  }
}

variable "ubuntu_lts_version" {
  description = "Ubuntu LTS version for AMI lookup (for example: 24.04 or 22.04)"
  type        = string
  default     = "24.04"
}

variable "enable_iam_instance_profile" {
  description = "Create and attach an IAM instance profile"
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository holding the application image"
  type        = string
  default     = "coika/auth_service"
}

variable "primary_region" {
  description = "Primary region of this stack. In any other region (disaster recovery), IAM names get a region suffix because IAM is global"
  type        = string
  default     = "eu-west-1"
}

variable "ssh_public_key" {
  description = "Optional SSH public key. If set, Terraform creates the key pair named key_name in this region (needed in a DR region, where the key pair does not exist)"
  type        = string
  default     = null
}

variable "ecr_replication_regions" {
  description = "Regions to which pushed images of the application repository are replicated (for example: [\"eu-central-1\"]). Empty disables replication"
  type        = list(string)
  default     = []
}

variable "github_oidc_subject_prefix" {
  description = "OIDC subject prefix of the GitHub repository allowed to assume the CI roles (as emitted in the token sub claim)"
  type        = string
  default     = "repo:acortescab@289379741/coika-auth_service-infra@1387194623"
}

variable "github_app_oidc_subjects" {
  description = "OIDC subjects (token sub claim) of the application repository allowed to assume the role that pushes images to ECR"
  type        = list(string)
  default = [
    "repo:acortescab@289379741/coika-auth_service@1261187863:ref:refs/heads/main",
    "repo:acortescab@289379741/coika-auth_service@1261187863:environment:prod",
  ]
}

variable "github_plan_environment" {
  description = "GitHub environment whose jobs may assume the read-only plan role (no approvals needed)"
  type        = string
  default     = "plan"
}

variable "github_apply_environment" {
  description = "GitHub environment whose jobs may assume the apply role"
  type        = string
  default     = "production"
}

variable "ci_allowed_regions" {
  description = "Regions where the CI roles may manage EC2 and ECR. Add the DR region here (and apply with admin credentials) before deploying there"
  type        = list(string)
  default     = ["eu-west-1"]
}

variable "tfstate_bucket_name" {
  description = "S3 bucket holding the Terraform state (must match backend.tf); the CI roles get access to it"
  type        = string
  default     = "coika-auth-tfstate-s3-290294660813-eu-west-1-an"
}

variable "extra_tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}