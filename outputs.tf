output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.docker_host.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.docker_host.private_ip
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance (if assigned)"
  value       = var.assign_public_ip ? aws_eip.docker_host[0].public_ip : aws_instance.docker_host.public_ip
}

output "security_group_id" {
  description = "ID of the security group attached to the EC2 instance"
  value       = aws_security_group.ec2_host.id
}

output "db_instance_id" {
  description = "ID of the database EC2 instance"
  value       = aws_instance.database.id
}

output "db_private_ip" {
  description = "Private IP of the database host (use it as the PostgreSQL host in the API configuration)"
  value       = aws_instance.database.private_ip
}

output "db_security_group_id" {
  description = "ID of the security group attached to the database host"
  value       = aws_security_group.database.id
}

output "private_subnet_id" {
  description = "ID of the private subnet hosting the database"
  value       = aws_subnet.private.id
}

output "ecr_repository_url" {
  description = "URL of the application ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "ci_plan_role_arn" {
  description = "Role for the AWS_PLAN_ROLE_TO_ASSUME GitHub secret"
  value       = aws_iam_role.ci["plan"].arn
}

output "ci_apply_role_arn" {
  description = "Role for the AWS_ROLE_TO_ASSUME GitHub secret"
  value       = aws_iam_role.ci["apply"].arn
}

output "app_cd_role_arn" {
  description = "Role for the application repository's GitHub Actions to push images to ECR"
  value       = aws_iam_role.app_cd.arn
}

output "iam_role_name" {
  description = "Name of the IAM role attached to the instance profile"
  value       = var.enable_iam_instance_profile ? aws_iam_role.ec2_role[0].name : null
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = var.enable_iam_instance_profile ? aws_iam_instance_profile.ec2_profile[0].name : null
}
