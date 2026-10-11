data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_partition" "current" {}

resource "aws_vpc" "mock_bank" {
  cidr_block           = var.mock_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-mock-bank-vpc"
  }
}

resource "aws_internet_gateway" "mock_bank" {
  vpc_id = aws_vpc.mock_bank.id

  tags = {
    Name = "${var.name_prefix}-mock-bank-igw"
  }
}

resource "aws_subnet" "mock_bank" {
  vpc_id                  = aws_vpc.mock_bank.id
  availability_zone       = var.mock_availability_zone
  cidr_block              = cidrsubnet(var.mock_vpc_cidr, 8, 1)
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-mock-bank-subnet"
  }
}

resource "aws_route_table" "mock_bank" {
  vpc_id = aws_vpc.mock_bank.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mock_bank.id
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank-rt"
  }
}

resource "aws_route_table_association" "mock_bank" {
  subnet_id      = aws_subnet.mock_bank.id
  route_table_id = aws_route_table.mock_bank.id
}

resource "aws_vpc_peering_connection" "main" {
  vpc_id      = var.main_vpc_id
  peer_vpc_id = aws_vpc.mock_bank.id
  auto_accept = true

  tags = {
    Name = "${var.name_prefix}-main-mock-bank-peering"
  }
}

resource "aws_route" "main_to_mock_bank" {
  count = length(var.main_app_route_table_ids)

  route_table_id            = var.main_app_route_table_ids[count.index]
  destination_cidr_block    = var.mock_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}

resource "aws_route" "mock_bank_to_main" {
  route_table_id            = aws_route_table.mock_bank.id
  destination_cidr_block    = var.main_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}

resource "aws_security_group" "mock_bank" {
  name        = "${var.name_prefix}-mock-bank"
  description = "Mock Bank API from EKS App Private subnets only; no inbound SSH."
  vpc_id      = aws_vpc.mock_bank.id

  egress {
    description = "SSM, ECR, and package downloads via Internet Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_subnets" {
  for_each = toset(var.main_app_subnet_cidrs)

  security_group_id = aws_security_group.mock_bank.id
  cidr_ipv4         = each.value
  description       = "Mock Bank API from an EKS App Private subnet"
  ip_protocol       = "tcp"
  from_port         = var.mock_bank_api_port
  to_port           = var.mock_bank_api_port
}

resource "aws_iam_role" "mock_bank" {
  name = "${var.name_prefix}-mock-bank-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mock_bank_ssm" {
  role       = aws_iam_role.mock_bank.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "mock_bank_ecr" {
  role       = aws_iam_role.mock_bank.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy" "mock_bank_secret" {
  name = "${var.name_prefix}-mock-bank-read-config"
  role = aws_iam_role.mock_bank.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.mock_bank_secret_arn
    }]
  })
}

resource "aws_iam_instance_profile" "mock_bank" {
  name = "${var.name_prefix}-mock-bank-profile"
  role = aws_iam_role.mock_bank.name
}

resource "aws_instance" "mock_bank" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.mock_bank.id
  vpc_security_group_ids      = [aws_security_group.mock_bank.id]
  iam_instance_profile        = aws_iam_instance_profile.mock_bank.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/mock-bank-user-data.sh.tftpl", {
    aws_region             = var.aws_region
    mock_bank_image        = var.mock_bank_image
    mock_bank_secret_arn   = var.mock_bank_secret_arn
    mock_bank_api_port     = var.mock_bank_api_port
    docker_compose_version = var.docker_compose_version
  })

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size_gib
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mock_bank_ssm,
    aws_iam_role_policy_attachment.mock_bank_ecr,
    aws_iam_role_policy.mock_bank_secret,
    aws_route.mock_bank_to_main,
  ]
}
