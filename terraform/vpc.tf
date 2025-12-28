# VPC
resource "aws_vpc" "psql-update-vpc" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = "false"
  instance_tenancy                 = "default"
  enable_dns_hostnames             = true
  enable_dns_support               = true
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.psql-update-vpc.id

  tags = {
    Name = "psql-update-igw"
  }
}

# Public Subnet (for NAT Gateway)
resource "aws_subnet" "public-subnet-a" {
  vpc_id                  = aws_vpc.psql-update-vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "psql-update-public-subnet-a"
  }
}


# NAT Gateway
resource "aws_nat_gateway" "nat" {
  vpc_id            = aws_vpc.psql-update-vpc.id
  availability_mode = "regional"

  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "psql-update-natgw"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.psql-update-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "psql-update-public-rt"
  }
}

resource "aws_route_table_association" "public-a" {
  subnet_id      = aws_subnet.public-subnet-a.id
  route_table_id = aws_route_table.public.id
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.psql-update-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "psql-update-private-rt"
  }
}

# Private Subnets
resource "aws_subnet" "private-subnet-bastion-a" {
  vpc_id            = aws_vpc.psql-update-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "psql-update-private-bastion-a"
  }
}

resource "aws_subnet" "private-subnet-aurora-a" {
  vpc_id            = aws_vpc.psql-update-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "psql-update-private-aurora-a"
  }
}

resource "aws_subnet" "private-subnet-aurora-c" {
  vpc_id            = aws_vpc.psql-update-vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}c"

  tags = {
    Name = "psql-update-private-aurora-c"
  }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private-bastion-a" {
  subnet_id      = aws_subnet.private-subnet-bastion-a.id
  route_table_id = aws_route_table.private.id
}


