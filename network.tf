// Private network for the database. It lives in the default VPC, so the API host (public
// subnet) reaches it over the VPC's local route. The database has no public address and the
// subnet has no route to the internet gateway; outbound traffic (apt, Docker images) goes
// through a NAT gateway placed in the public subnet.

data "aws_subnet" "public" {
  id = local.selected_subnet_id
}

locals {
  private_subnet_az = coalesce(var.db_availability_zone, data.aws_subnet.public.availability_zone)
}

resource "aws_subnet" "private" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = local.private_subnet_az
  map_public_ip_on_launch = false

  tags = merge(
    {
      Name      = "${var.instance_name}-private-subnet"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = merge(
    {
      Name      = "${var.instance_name}-nat-eip"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_nat_gateway" "private" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = local.selected_subnet_id

  tags = merge(
    {
      Name      = "${var.instance_name}-nat"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.default.id

  tags = merge(
    {
      Name      = "${var.instance_name}-private-rt"
      Project   = var.project_name
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private[0].id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
