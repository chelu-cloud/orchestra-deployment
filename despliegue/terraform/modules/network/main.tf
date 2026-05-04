data "aws_region" "current" {}

resource "aws_vpc" "vpc_a"{
    cidr_block = var.cidr_block_vpc_a
    enable_dns_support   = true  # Activa el servidor DNS de AWS 
    enable_dns_hostnames = true  # Asigna nombres DNS a los recursos con IP pública
    tags = {
        Name = "VPC A - Chelu"
    }
}

resource "aws_subnet" "a_subnet_public" {
    count = length(var.public_subnet_cidr_a)
    vpc_id = aws_vpc.vpc_a.id
    cidr_block = var.public_subnet_cidr_a[count.index]
    availability_zone = var.az[count.index]
    map_public_ip_on_launch = true

    tags = {
        Name = "Subnet ${count.index} publica VPC A - Chelu"
    }
}

resource "aws_subnet" "a_subnet_private_app" {
    count = length(var.private_subnet_cidr_a_app)
    vpc_id = aws_vpc.vpc_a.id
    cidr_block = var.private_subnet_cidr_a_app[count.index]
    availability_zone = var.az[count.index]

    tags = {
        Name = "Subnet ${count.index} app VPC A - Chelu"
    }
}

resource "aws_subnet" "a_subnet_private_data" {
    count = length(var.private_subnet_cidr_a_data)
    vpc_id = aws_vpc.vpc_a.id
    cidr_block = var.private_subnet_cidr_a_data[count.index]
    availability_zone = var.az[count.index]

    tags = {
        Name = "Subnet ${count.index} datos VPC A - Chelu"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc_a.id
    tags = {
      Name = "Igw VPC A - Chelu"
    }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.a_subnet_public[0].id 
  depends_on    = [aws_internet_gateway.igw]
}

# -----------------------------------------------
# ROUTE TABLES
# -----------------------------------------------

resource "aws_route_table" "rt_pub_a" { // Cada route table pertenece a una subnet, la cual es su origen
  vpc_id = aws_vpc.vpc_a.id

  route {
    cidr_block = "0.0.0.0/0" // Destino 
    gateway_id = aws_internet_gateway.igw.id // Puerta de salida
  }

  tags = {
    Name = "public rt az 1"
  }
}

resource "aws_route_table" "rt_priv_a" { 
  vpc_id = aws_vpc.vpc_a.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private rt az 1"
  }
}

resource "aws_route_table" "rt_priv_data" {
  vpc_id = aws_vpc.vpc_a.id

  tags = { Name = "private data rt" }
}

resource "aws_route_table_association" "public" {
    count          = length(var.public_subnet_cidr_a)
    subnet_id      = aws_subnet.a_subnet_public[count.index].id
    route_table_id = aws_route_table.rt_pub_a.id 
}

resource "aws_route_table_association" "private" {
    count          = length(var.private_subnet_cidr_a_app)
    subnet_id      = aws_subnet.a_subnet_private_app[count.index].id
    route_table_id = aws_route_table.rt_priv_a.id 
}

resource "aws_route_table_association" "private_data" {
  count          = length(var.private_subnet_cidr_a_data)
  subnet_id      = aws_subnet.a_subnet_private_data[count.index].id
  route_table_id = aws_route_table.rt_priv_data.id
}

# -----------------------------------------------
# SECURITY GROUPS
# -----------------------------------------------

resource "aws_security_group" "backend" {
  name        = "backend_sg"
  description = "Backend security group. Allow egress to ethernet for downloading libraries"
  vpc_id      = aws_vpc.vpc_a.id

  tags = {
    Name = "sg-backend"
  }
}

resource "aws_security_group" "data-base" {
    name = "data-base sg"
    description = "Data base security group. Allow egress to ethernet for downloading libraries"
    vpc_id = aws_vpc.vpc_a.id

    tags = {
        Name = "sg-database"
    }
}

resource "aws_security_group_rule" "bakcend-egress" {
    security_group_id = aws_security_group.backend.id

    type = "egress"

    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0

    protocol = "-1"
}

resource "aws_security_group_rule" "db-ingress" {
    security_group_id = aws_security_group.data-base.id
    source_security_group_id = aws_security_group.backend.id

    type = "ingress"

    from_port = 5432
    to_port = 5432

    protocol = "tcp"
}

resource "aws_security_group_rule" "db_egress_local" {
  security_group_id = aws_security_group.data-base.id

  cidr_blocks       = [var.cidr_block_vpc_a]
  type              = "egress"
  from_port         = 0
  to_port           = 0

  protocol          = "-1" 
}



