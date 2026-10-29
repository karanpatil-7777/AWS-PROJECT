# Find latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_az = data.aws_availability_zones.available.names[0]
}

# =========================================================================
# VPC A (10.10.0.0/16) - Requester VPC
# =========================================================================
resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = {
    Name = "ewb-vpc-a"
  }
}

# Subnets in VPC A
resource "aws_subnet" "subnet_a_public" {
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = var.subnet_a_public_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = true

  tags = {
    Name = "ewb-a-public"
  }
}

resource "aws_subnet" "subnet_a_private" {
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = var.subnet_a_private_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = false

  tags = {
    Name = "ewb-a-private"
  }
}

# Internet Gateway for VPC A
resource "aws_internet_gateway" "igw_a" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "ewb-igw-a"
  }
}

# Route Tables for VPC A
resource "aws_route_table" "rt_a_public" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "ewb-rt-a-public"
  }
}

resource "aws_route_table" "rt_a_private" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "ewb-rt-a-private"
  }
}

# Subnet Associations for VPC A
resource "aws_route_table_association" "assoc_a_public" {
  subnet_id      = aws_subnet.subnet_a_public.id
  route_table_id = aws_route_table.rt_a_public.id
}

resource "aws_route_table_association" "assoc_a_private" {
  subnet_id      = aws_subnet.subnet_a_private.id
  route_table_id = aws_route_table.rt_a_private.id
}

# Default Internet Route for Public Route Table
resource "aws_route" "route_a_public_internet" {
  route_table_id         = aws_route_table.rt_a_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_a.id
}

# =========================================================================
# VPC B (10.20.0.0/16) - Accepter VPC (No Internet Gateway)
# =========================================================================
resource "aws_vpc" "vpc_b" {
  cidr_block           = var.vpc_b_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = {
    Name = "ewb-vpc-b"
  }
}

# Subnet in VPC B
resource "aws_subnet" "subnet_b_private" {
  vpc_id                  = aws_vpc.vpc_b.id
  cidr_block              = var.subnet_b_private_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = false

  tags = {
    Name = "ewb-b-private"
  }
}

# Route Table for VPC B
resource "aws_route_table" "rt_b_private" {
  vpc_id = aws_vpc.vpc_b.id

  tags = {
    Name = "ewb-rt-b-private"
  }
}

resource "aws_route_table_association" "assoc_b_private" {
  subnet_id      = aws_subnet.subnet_b_private.id
  route_table_id = aws_route_table.rt_b_private.id
}

# =========================================================================
# VPC Peering Connection (Same Account / Same Region)
# =========================================================================
resource "aws_vpc_peering_connection" "peer_a_b" {
  vpc_id      = aws_vpc.vpc_a.id
  peer_vpc_id = aws_vpc.vpc_b.id
  auto_accept = true

  tags = {
    Name = "ewb-a-b-peer"
  }
}

# Peering Routes
# 1. VPC A Public Subnet -> VPC B (10.20.0.0/16)
resource "aws_route" "route_a_public_peering" {
  route_table_id            = aws_route_table.rt_a_public.id
  destination_cidr_block    = var.vpc_b_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer_a_b.id
}

# 2. VPC A Private Subnet -> VPC B (10.20.0.0/16)
resource "aws_route" "route_a_private_peering" {
  route_table_id            = aws_route_table.rt_a_private.id
  destination_cidr_block    = var.vpc_b_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer_a_b.id
}

# 3. Return Route: VPC B Private Subnet -> VPC A (10.10.0.0/16)
resource "aws_route" "route_b_private_peering" {
  route_table_id            = aws_route_table.rt_b_private.id
  destination_cidr_block    = var.vpc_a_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer_a_b.id
}

# =========================================================================
# Security Groups
# =========================================================================
# 1. Bastion Host Security Group (VPC A)
resource "aws_security_group" "sg_bastion" {
  name        = "ewb-sg-bastion"
  description = "Security group for public bastion host"
  vpc_id      = aws_vpc.vpc_a.id

  ingress {
    description = "SSH from Admin IPv4"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_source_cidr]
  }

  egress {
    description = "Default allow-all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ewb-sg-bastion"
  }
}

# 2. App-A Security Group (VPC A)
resource "aws_security_group" "sg_app_a" {
  name        = "ewb-sg-app-a"
  description = "Security group for App-A private host"
  vpc_id      = aws_vpc.vpc_a.id

  ingress {
    description = "SSH from Bastion private IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.bastion_private_ip}/32"]
  }

  ingress {
    description = "Custom ICMP Echo Request from App-B"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["${var.app_b_private_ip}/32"]
  }

  egress {
    description = "Default allow-all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ewb-sg-app-a"
  }
}

# 3. App-B Security Group (VPC B)
resource "aws_security_group" "sg_app_b" {
  name        = "ewb-sg-app-b"
  description = "Security group for App-B private host"
  vpc_id      = aws_vpc.vpc_b.id

  ingress {
    description = "SSH from Bastion private IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.bastion_private_ip}/32"]
  }

  ingress {
    description = "Custom ICMP Echo Request from App-A"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["${var.app_a_private_ip}/32"]
  }

  egress {
    description = "Default allow-all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ewb-sg-app-b"
  }
}

# =========================================================================
# EC2 Instances (Static IP assignment as defined in Workbook)
# =========================================================================
# Bastion Host (10.10.1.10)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.subnet_a_public.id
  private_ip                  = var.bastion_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg_bastion.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  tags = {
    Name = "ewb-bastion"
  }
}

# App-A Host (10.10.2.10)
resource "aws_instance" "app_a" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.subnet_a_private.id
  private_ip                  = var.app_a_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.sg_app_a.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  tags = {
    Name = "ewb-app-a"
  }
}

# App-B Host (10.20.1.10)
resource "aws_instance" "app_b" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.subnet_b_private.id
  private_ip                  = var.app_b_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.sg_app_b.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  tags = {
    Name = "ewb-app-b"
  }
}
