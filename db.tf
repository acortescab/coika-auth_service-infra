// PostgreSQL host: same Docker-ready Ubuntu image, but in the private subnet with no public IP.
// The bootstrap installs the db/ folder and starts PostgreSQL (docker compose, under systemd) on its own.
// Reach it with SSM Session Manager, or over SSH hopping through the API host.
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu_lts.id
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  key_name                    = local.key_name
  vpc_security_group_ids      = [aws_security_group.database.id]
  iam_instance_profile        = var.enable_iam_instance_profile ? aws_iam_instance_profile.db_profile[0].name : null

  root_block_device {
    encrypted   = true
    volume_size = var.db_root_volume_size
    volume_type = var.root_volume_type
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  // Shared Docker bootstrap, then PostgreSQL itself (db/ folder + systemd + backup cron).
  user_data = join("\n", [
    file("${path.module}/user_data.sh"),
    templatefile("${path.module}/db_bootstrap.sh", {
      // gzip keeps user_data well under the 16 KB limit
      files         = { for f in fileset("${path.module}/db", "{docker-compose.yml,*.sh,settings.env.example}") : f => base64gzip(file("${path.module}/db/${f}")) }
      backup_bucket = aws_s3_bucket.db_snapshots.bucket
      backup_cron   = var.db_backup_cron
      ssm_prefix    = local.ssm_prefix
    }),
  ])

  // The data lives on the root disk, which is deleted with the instance: a newer AMI or an edited
  // bootstrap script must never replace it. Replacing the host on purpose
  // (terraform apply -replace=aws_instance.database) means restoring the data from the S3 dumps.
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
