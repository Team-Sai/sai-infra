locals {
  public_subnet_cidr  = cidrsubnet(var.mock_vpc_cidr, 8, 1)
  private_subnet_cidr = cidrsubnet(var.mock_vpc_cidr, 8, 2)
  database_private_ip = cidrhost(local.private_subnet_cidr, 10)
  data_volume_tag     = "${var.name_prefix}-mock-bank-database"

  # Terraform has no cidrcontains function. Convert both IPv4 CIDR boundaries to integers for overlap checks.
  mock_vpc_start_octets = [for octet in split(".", cidrhost(var.mock_vpc_cidr, 0)) : tonumber(octet)]
  mock_vpc_end_octets   = [for octet in split(".", cidrhost(var.mock_vpc_cidr, -1)) : tonumber(octet)]
  main_vpc_start_octets = [for octet in split(".", cidrhost(var.main_vpc_cidr, 0)) : tonumber(octet)]
  main_vpc_end_octets   = [for octet in split(".", cidrhost(var.main_vpc_cidr, -1)) : tonumber(octet)]
  mock_vpc_start        = sum([for index, octet in local.mock_vpc_start_octets : octet * pow(256, 3 - index)])
  mock_vpc_end          = sum([for index, octet in local.mock_vpc_end_octets : octet * pow(256, 3 - index)])
  main_vpc_start        = sum([for index, octet in local.main_vpc_start_octets : octet * pow(256, 3 - index)])
  main_vpc_end          = sum([for index, octet in local.main_vpc_end_octets : octet * pow(256, 3 - index)])
}

# 사용자 지정 브라우저 도메인 입력 누락을 apply 전에 차단합니다.
resource "terraform_data" "configuration_guard" {
  input = var.mock_vpc_cidr

  lifecycle {
    precondition {
      condition     = local.mock_vpc_start > local.main_vpc_end || local.main_vpc_start > local.mock_vpc_end
      error_message = "Mock Bank VPC CIDR은 SAI 주 VPC CIDR과 겹치면 안 됩니다. VPC Peering 라우팅이 동작하지 않습니다."
    }

    precondition {
      condition = (
        var.viewer_domain_name == null
        ? var.viewer_certificate_arn == null && var.public_hosted_zone_id == null
        : can(regex(
          "^arn:aws:acm:us-east-1:[0-9]{12}:certificate/.+$",
          coalesce(var.viewer_certificate_arn, "")
        )) && var.public_hosted_zone_id != null
      )
      error_message = "사용자 지정 브라우저 도메인에는 us-east-1 ACM 인증서 ARN과 Route 53 공개 Hosted Zone ID가 필요합니다."
    }
  }
}

resource "aws_vpc" "mock_bank" {
  cidr_block           = var.mock_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-mock-bank-vpc"
  }

  depends_on = [terraform_data.configuration_guard]
}

# CloudFront VPC Origin이 이 VPC의 사설 EC2를 원본으로 사용할 수 있도록 IGW를 연결합니다.
# EC2가 있는 private subnet에는 IGW 기본 경로를 만들지 않습니다.
resource "aws_internet_gateway" "mock_bank" {
  vpc_id = aws_vpc.mock_bank.id

  tags = {
    Name = "${var.name_prefix}-mock-bank-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.mock_bank.id
  availability_zone       = var.mock_availability_zone
  cidr_block              = local.public_subnet_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-mock-bank-nat-public"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.mock_bank.id
  availability_zone       = var.mock_availability_zone
  cidr_block              = local.private_subnet_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-mock-bank-private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.mock_bank.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mock_bank.id
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-mock-bank-nat-eip"
  }
}

resource "aws_nat_gateway" "mock_bank" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.name_prefix}-mock-bank-nat"
  }

  depends_on = [aws_internet_gateway.mock_bank]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.mock_bank.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mock_bank.id
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpc_peering_connection" "main" {
  vpc_id      = var.main_vpc_id
  peer_vpc_id = aws_vpc.mock_bank.id
  auto_accept = true

  tags = {
    Name = "${var.name_prefix}-main-mock-bank-peering"
  }
}

# SAI App Private 서브넷에서만 Mock Bank 내부 TLS API로 이동할 수 있도록 라우팅합니다.
resource "aws_route" "main_to_mock_bank" {
  count = length(var.main_app_route_table_ids)

  route_table_id            = var.main_app_route_table_ids[count.index]
  destination_cidr_block    = var.mock_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}

resource "aws_route" "mock_bank_to_main" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.main_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}

resource "aws_security_group" "mock_bank" {
  name        = "${var.name_prefix}-mock-bank"
  description = "CloudFront VPC Origin web traffic and SAI App Private TLS API only; no SSH."
  vpc_id      = aws_vpc.mock_bank.id

  egress {
    description = "AWS APIs and package downloads through the private subnet NAT route"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_subnets_api" {
  for_each = toset(var.main_app_subnet_cidrs)

  security_group_id = aws_security_group.mock_bank.id
  cidr_ipv4         = each.value
  description       = "SAI App Private subnet to Mock Bank TLS API"
  ip_protocol       = "tcp"
  from_port         = var.mock_bank_api_port
  to_port           = var.mock_bank_api_port
}

# TCP 8080은 CloudFront VPC Origin 보안 그룹 규칙을 만든 뒤 edge.tf에서만 허용합니다.
