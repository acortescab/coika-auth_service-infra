resource "aws_security_group" "ec2_host" {
  name        = "${var.instance_name}-sg"
  description = "Security group for ${var.instance_name}"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    {
      Name        = "${var.instance_name}-sg"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.ec2_host.id
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  for_each          = toset(var.app_ingress_cidrs)
  security_group_id = aws_security_group.ec2_host.id
  cidr_ipv4         = each.value
  from_port         = 8000
  ip_protocol       = "tcp"
  to_port           = 8000
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ec2_host.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Database: reachable only from the API host's security group.
resource "aws_security_group" "database" {
  name        = "${var.db_instance_name}-sg"
  description = "Security group for ${var.db_instance_name}"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    {
      Name        = "${var.db_instance_name}-sg"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags,
  )
}

resource "aws_vpc_security_group_ingress_rule" "db_postgres_from_app" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.ec2_host.id
  from_port                    = var.db_port
  ip_protocol                  = "tcp"
  to_port                      = var.db_port
}

# SSH only through the API host (used as a jump host).
resource "aws_vpc_security_group_ingress_rule" "db_ssh_from_app" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.ec2_host.id
  from_port                    = 22
  ip_protocol                  = "tcp"
  to_port                      = 22
}

resource "aws_vpc_security_group_egress_rule" "db_allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.database.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}