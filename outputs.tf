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

output "iam_role_name" {
  description = "Name of the IAM role attached to the instance profile"
  value       = var.enable_iam_instance_profile ? aws_iam_role.ec2_role[0].name : null
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = var.enable_iam_instance_profile ? aws_iam_instance_profile.ec2_profile[0].name : null
}
