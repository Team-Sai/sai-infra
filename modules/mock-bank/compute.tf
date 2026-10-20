data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_partition" "current" {}

locals {
  mock_bank_tiers = toset(["web", "was", "database"])
}

resource "aws_iam_role" "tier" {
  for_each = local.mock_bank_tiers
  name     = "${var.name_prefix}-mock-bank-${each.key}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "tier_ssm" {
  for_each   = local.mock_bank_tiers
  role       = aws_iam_role.tier[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Only WAS pulls the application image and reads the TLS certificate. The DB
# host reads the existing app secret only to initialize the configured DB user.
resource "aws_iam_role_policy" "was_runtime" {
  name = "${var.name_prefix}-mock-bank-was-runtime-read"
  role = aws_iam_role.tier["was"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetEcrAuthorizationToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PullOnlyMockBankImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = var.mock_bank_ecr_repository_arn
      },
      {
        Sid      = "ReadApplicationAndTlsSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.mock_bank_secret_arn, var.mock_bank_api_certificate_secret_arn]
      },
    ]
  })
}

resource "aws_iam_role_policy" "database_runtime" {
  name = "${var.name_prefix}-mock-bank-database-secret-read"
  role = aws_iam_role.tier["database"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadConfiguredDatabaseCredentials"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.mock_bank_secret_arn
    }]
  })
}

resource "aws_iam_instance_profile" "tier" {
  for_each = local.mock_bank_tiers
  name     = "${var.name_prefix}-mock-bank-${each.key}-profile"
  role     = aws_iam_role.tier[each.key].name
}

# Keep this resource address and tag stable so the existing encrypted data
# volume and DLM snapshot policy survive the EC2 tier split.
resource "aws_ebs_volume" "database" {
  availability_zone = var.mock_availability_zone
  size              = var.data_volume_size_gib
  type              = "gp3"
  encrypted         = true

  tags = {
    Name         = local.data_volume_tag
    BackupPolicy = local.data_volume_tag
    DataPurpose  = "Mock Bank MariaDB demo data"
    DataClass    = "SyntheticOnly"
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.web.id
  private_ip                  = local.web_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.tier["web"].name

  user_data = templatefile("${path.module}/web-user-data.sh.tftpl", {
    nginx_config = templatefile("${path.module}/web-nginx.conf.tftpl", {
      origin_port    = var.mock_bank_origin_port
      was_private_ip = local.was_private_ip
      was_app_port   = var.mock_bank_app_port
    })
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
    Name = "${var.name_prefix}-mock-bank-web"
    Tier = "web"
  }

  depends_on = [
    aws_iam_role_policy_attachment.tier_ssm,
    aws_route_table_association.private,
  ]
}

resource "aws_instance" "was" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.was.id
  private_ip                  = local.was_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.was.id]
  iam_instance_profile        = aws_iam_instance_profile.tier["was"].name

  user_data = templatefile("${path.module}/was-user-data.sh.tftpl", {
    aws_region                           = var.aws_region
    mock_bank_image                      = var.mock_bank_image
    mock_bank_secret_arn                 = var.mock_bank_secret_arn
    mock_bank_api_certificate_secret_arn = var.mock_bank_api_certificate_secret_arn
    mock_bank_api_port                   = var.mock_bank_api_port
    mock_bank_app_port                   = var.mock_bank_app_port
    mock_bank_api_hostname               = var.mock_bank_api_hostname
    was_private_ip                       = local.was_private_ip
    database_private_ip                  = local.database_private_ip
    nginx_config = templatefile("${path.module}/was-nginx.conf.tftpl", {
      api_hostname   = var.mock_bank_api_hostname
      api_port       = var.mock_bank_api_port
      app_port       = var.mock_bank_app_port
      was_private_ip = local.was_private_ip
    })
    docker_compose_version = var.docker_compose_version
    docker_compose_sha256  = var.docker_compose_sha256
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
    Name = "${var.name_prefix}-mock-bank-was"
    Tier = "was"
  }

  depends_on = [
    aws_iam_role_policy_attachment.tier_ssm,
    aws_iam_role_policy.was_runtime,
    aws_route_table_association.private,
    aws_route.mock_bank_to_main,
  ]
}

resource "aws_instance" "database" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.database.id
  private_ip                  = local.database_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.database.id]
  iam_instance_profile        = aws_iam_instance_profile.tier["database"].name

  user_data = templatefile("${path.module}/database-user-data.sh.tftpl", {
    aws_region             = var.aws_region
    mock_bank_secret_arn   = var.mock_bank_secret_arn
    database_volume_id     = aws_ebs_volume.database.id
    database_private_ip    = local.database_private_ip
    mariadb_image          = var.mariadb_image
    docker_compose_version = var.docker_compose_version
    docker_compose_sha256  = var.docker_compose_sha256
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
    Name        = "${var.name_prefix}-mock-bank-database"
    Tier        = "database"
    DataPurpose = "SyntheticOnlyMockBankDemo"
  }

  depends_on = [
    aws_iam_role_policy_attachment.tier_ssm,
    aws_iam_role_policy.database_runtime,
    aws_route_table_association.private,
    aws_route.mock_bank_to_main,
  ]
}

resource "aws_volume_attachment" "database" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.database.id
  instance_id                    = aws_instance.database.id
  stop_instance_before_detaching = true
}
