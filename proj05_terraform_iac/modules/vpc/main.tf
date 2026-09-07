# vpc
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

# public subnets
resource "aws_subnet" "public_subnet_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.pub_sub_one_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "Public-Subnet-AZ1-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_subnet" "public_subnet_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.pub_sub_two_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "Public-Subnet-AZ2-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

# private subnets
resource "aws_subnet" "private_subnet_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.priv_sub_one_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "Private-Subnet-AZ1-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_subnet" "private_subnet_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.priv_sub_two_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "Private-Subnet-AZ2-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

# isolated subnets
resource "aws_subnet" "isolated_subnet_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.iso_sub_one_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "Isolated-Subnet-AZ1-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_subnet" "isolated_subnet_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.iso_sub_two_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "Isolated-Subnet-AZ2-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

# igw
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "proj05-igw-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

# route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.pub_route_cidr
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "proj05-public-rt-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "pub_rt_assoc_az1" {
  subnet_id      = aws_subnet.public_subnet_az1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "pub_rt_assoc_az2" {
  subnet_id      = aws_subnet.public_subnet_az2.id
  route_table_id = aws_route_table.public_route_table.id
}

# first route table
resource "aws_eip" "my_eip_one" {
  domain = "vpc"

  tags = {
    Name        = "proj05-eip-one-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_nat_gateway" "my_nat_one" {
  allocation_id = aws_eip.my_eip_one.id
  subnet_id     = aws_subnet.public_subnet_az1.id

  tags = {
    Name        = "proj05-nat-one-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private_route_table_one" {
  vpc_id = aws_vpc.main.id

  route {
    nat_gateway_id = aws_nat_gateway.my_nat_one.id
    cidr_block     = var.pub_route_cidr
  }

  tags = {
    Name        = "proj05-private-rt-one-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "priv_rt_assoc_az1" {
  subnet_id      = aws_subnet.private_subnet_az1.id
  route_table_id = aws_route_table.private_route_table_one.id
}

# second private route table
resource "aws_eip" "my_eip_two" {
  domain = "vpc"

  tags = {
    Name        = "proj05-eip-two-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_nat_gateway" "my_nat_two" {
  allocation_id = aws_eip.my_eip_two.id
  subnet_id     = aws_subnet.public_subnet_az2.id

  tags = {
    Name        = "proj05-nat-two-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private_route_table_two" {
  vpc_id = aws_vpc.main.id

  route {
    nat_gateway_id = aws_nat_gateway.my_nat_two.id
    cidr_block     = var.pub_route_cidr
  }

  tags = {
    Name        = "proj05-private-rt-two-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "priv_rt_assoc_az2" {
  subnet_id      = aws_subnet.private_subnet_az2.id
  route_table_id = aws_route_table.private_route_table_two.id
}

# iso table
resource "aws_route_table" "iso_route_table" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "proj05-isolated-rt-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "iso_rt_assoc_az1" {
  subnet_id      = aws_subnet.isolated_subnet_az1.id
  route_table_id = aws_route_table.iso_route_table.id
}

resource "aws_route_table_association" "iso_rt_assoc_az2" {
  subnet_id      = aws_subnet.isolated_subnet_az2.id
  route_table_id = aws_route_table.iso_route_table.id
}