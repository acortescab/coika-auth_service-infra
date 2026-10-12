// PostgreSQL host: same Docker-ready Ubuntu image, but in the private subnet with no public IP.
// Like the API host, Terraform only prepares the machine; PostgreSQL itself runs with docker compose.
// Reach it with SSM Session Manager, or over SSH hopping through the API host.
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu_lts.id
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  key_name                    = local.key_name
  vpc_security_group_ids      = [aws_security_group.database.id]
  iam_instance_profile        = var.enable_iam_instance_profile ? aws_iam_instance_profile.ec2_profile[0].name : null

  root_block_device {
    encrypted   = true
    volume_size = var.db_root_volume_size
    volume_type = var.root_volume_type
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  // Shared Docker bootstrap, followed by formatting and mounting the data volume.
  user_data = join("\n", [
    file("${path.module}/user_data.sh"),
    templatefile("${path.module}/db_data_volume.sh", {
      volume_id_nodash = replace(aws_ebs_volume.db_data.id, "-", "")
      mount_path       = var.db_data_mount_path
    }),
  ])

  // The instance holds the data: a newer AMI or an edited bootstrap script must never replace it.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  # The bootstrap needs outbound internet (apt, Docker) from the first boot.
  depends_on = [aws_route.private_nat, aws_route_table_association.private]

  tags = merge(
    {
      Name        = var.db_instance_name
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

// PostgreSQL data lives on its own encrypted volume, independent from the root disk.
resource "aws_ebs_volume" "db_data" {
  availability_zone = aws_subnet.private.availability_zone
  size              = var.db_data_volume_size
  type              = var.db_data_volume_type
  encrypted         = true
  kms_key_id        = var.db_data_kms_key_id

  tags = merge(
    {
      Name        = "${var.db_instance_name}-data"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

resource "aws_volume_attachment" "db_data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.db_data.id
  instance_id                    = aws_instance.database.id
  stop_instance_before_detaching = true
}
