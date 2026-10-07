locals {
  selected_subnet_id = var.subnet_id != null ? var.subnet_id : sort(data.aws_subnets.default_vpc_subnets.ids)[0]
}

resource "aws_instance" "docker_host" {
  ami                         = data.aws_ami.ubuntu_lts.id
  instance_type               = var.instance_type
  subnet_id                   = local.selected_subnet_id
  availability_zone           = var.availability_zone
  associate_public_ip_address = var.assign_public_ip
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.ec2_host.id]
  iam_instance_profile        = var.enable_iam_instance_profile ? aws_iam_instance_profile.ec2_profile[0].name : null

  root_block_device {
    encrypted   = true
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  tags = merge(
    {
      Name        = var.instance_name
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

# Stable public address: it survives instance replacement, so EC2_HOST / PROD_URL never go stale.
resource "aws_eip" "docker_host" {
  count = var.assign_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.docker_host.id

  tags = merge(
    {
      Name        = "${var.instance_name}-eip"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}
