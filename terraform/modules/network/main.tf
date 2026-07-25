resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  # Cross-variable checks live here because variable validation blocks may not
  # reference another variable on Terraform 1.5.
  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.azs)
      error_message = "public_subnet_cidrs must contain one CIDR per availability zone."
    }
  }

  tags = merge(
    { Name = "${var.name}-public-${count.index + 1}" },
    var.kubernetes_cluster_name == "" ? {} : {
      "kubernetes.io/cluster/${var.kubernetes_cluster_name}" = "shared"
      "kubernetes.io/role/elb"                               = "1"
    }
  )
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_cidrs) == length(var.azs)
      error_message = "private_subnet_cidrs must contain one CIDR per availability zone."
    }
  }

  tags = merge(
    { Name = "${var.name}-private-${count.index + 1}" },
    var.kubernetes_cluster_name == "" ? {} : {
      "kubernetes.io/cluster/${var.kubernetes_cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb"                      = "1"
    }
  )
}

resource "aws_subnet" "database" {
  count             = length(var.database_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  lifecycle {
    precondition {
      condition     = length(var.database_subnet_cidrs) == length(var.azs)
      error_message = "database_subnet_cidrs must contain one CIDR per availability zone."
    }
  }

  tags = { Name = "${var.name}-database-${count.index + 1}" }
}

locals {
  nat_gateway_count = var.nat_gateway_strategy == "per_az" ? length(var.azs) : 1
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = { Name = "${var.name}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${var.name}-nat-${count.index + 1}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.nat_gateway_strategy == "per_az" ? count.index : 0].id
  }

  tags = { Name = "${var.name}-private-rt-${count.index + 1}" }
}

resource "aws_route_table" "database" {
  count  = length(aws_subnet.database)
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-database-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}
