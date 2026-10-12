data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_partition" "current" {}

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

# ECR authorization token은 AWS가 Resource=*를 요구하지만 실제 이미지 읽기는 한 저장소로 제한합니다.
resource "aws_iam_role_policy" "mock_bank_runtime" {
  name = "${var.name_prefix}-mock-bank-runtime-read"
  role = aws_iam_role.mock_bank.id

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
        Sid    = "ReadOnlyConfiguredSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          var.mock_bank_secret_arn,
          var.mock_bank_api_certificate_secret_arn,
        ]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "mock_bank" {
  name = "${var.name_prefix}-mock-bank-profile"
  role = aws_iam_role.mock_bank.name
}

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

resource "aws_instance" "mock_bank" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.mock_bank.id]
  iam_instance_profile        = aws_iam_instance_profile.mock_bank.name

  user_data = templatefile("${path.module}/mock-bank-user-data.sh.tftpl", {
    aws_region                           = var.aws_region
    mock_bank_image                      = var.mock_bank_image
    mock_bank_secret_arn                 = var.mock_bank_secret_arn
    mock_bank_api_certificate_secret_arn = var.mock_bank_api_certificate_secret_arn
    mock_bank_api_port                   = var.mock_bank_api_port
    mock_bank_origin_port                = var.mock_bank_origin_port
    mock_bank_app_port                   = var.mock_bank_app_port
    mock_bank_api_hostname               = var.mock_bank_api_hostname
    nginx_config = templatefile("${path.module}/mock-bank-nginx.conf.tftpl", {
      api_hostname = var.mock_bank_api_hostname
      api_port     = var.mock_bank_api_port
      origin_port  = var.mock_bank_origin_port
      app_port     = var.mock_bank_app_port
    })
    database_volume_id     = aws_ebs_volume.database.id
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
    Name        = "${var.name_prefix}-mock-bank"
    DataPurpose = "SyntheticOnlyMockBankDemo"
  }

  depends_on = [
    aws_iam_role_policy_attachment.mock_bank_ssm,
    aws_iam_role_policy.mock_bank_runtime,
    aws_route_table_association.private,
    aws_route.mock_bank_to_main,
  ]
}

resource "aws_volume_attachment" "database" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.database.id
  instance_id = aws_instance.mock_bank.id
}
