data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy" "cluster_kms" {
  name = "${var.name_prefix}-eks-kms-grants"
  role = aws_iam_role.cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:CreateGrant", "kms:DescribeKey"]
      Resource = aws_kms_key.eks.arn
      Condition = {
        Bool = {
          "kms:GrantIsForAWSResource" = "true"
        }
      }
    }]
  })
}

resource "aws_iam_role" "nodes" {
  name = "${var.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-eks-control-plane"
  description = "EKS control plane access from nodes and the private Bastion."
  vpc_id      = var.vpc_id

  egress {
    description = "EKS control plane outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-eks-control-plane"
  }
}

resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-eks-nodes"
  description = "EKS node traffic. Database ports are opened separately by the data module."
  vpc_id      = var.vpc_id

  egress {
    description = "Node outbound traffic through the AZ-local NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-eks-nodes"
    # IP target 모드에서 AWS Load Balancer Controller가 Pod ENI의 SG를 찾습니다.
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
    "elbv2.k8s.aws/cluster"                        = "${var.name_prefix}-eks"
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion"
  description = "Private SSM-managed admin host; no inbound SSH is allowed."
  vpc_id      = var.vpc_id

  egress {
    description = "SSM HTTPS and EKS API access via the private route table"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-bastion"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_bastion" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.bastion.id
  description                  = "kubectl API from the private Bastion only"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.nodes.id
  description                  = "EKS control plane traffic from worker nodes"
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  description                  = "EKS control plane self communication"
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_cluster" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.cluster.id
  description                  = "Control plane to kubelet and node services"
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  description                  = "Node and pod traffic between worker nodes"
  ip_protocol                  = "-1"
}

resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.name_prefix}-eks-node-"
  update_default_version = true

  vpc_security_group_ids = [
    aws_security_group.nodes.id,
    aws_security_group.cluster.id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted             = true
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }
}

resource "aws_eks_cluster" "main" {
  name     = "${var.name_prefix}-eks"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.app_private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.cluster,
  ]
}

# EKS가 자동 생성하는 로그 그룹은 기본적으로 무기한 보관될 수 있어 먼저 만들고 보존 기간을 지정합니다.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name_prefix}-eks/cluster"
  retention_in_days = var.cluster_log_retention

  tags = {
    Name = "${var.name_prefix}-eks-control-plane-logs"
  }
}

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS Kubernetes secret encryption."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${var.name_prefix}-eks-secrets"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name_prefix}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_eks_addon" "pre_node" {
  for_each = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.value
  configuration_values        = each.value == "vpc-cni" ? jsonencode({ enableNetworkPolicy = "true" }) : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# CoreDNS는 실행될 Worker Node가 필요하므로 노드 그룹이 만들어진 뒤 설치합니다.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.initial]
}

# VPC CNI에는 Pod Identity 전용 역할을 줍니다. 앱 Pod가 노드 역할의
# 네트워크 변경 권한을 상속하지 않도록 노드 역할에서는 CNI 정책을 제거했습니다.
resource "aws_iam_role" "vpc_cni" {
  name = "${var.name_prefix}-vpc-cni-pod-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.main.arn
          "aws:RequestTag/kubernetes-namespace"       = "kube-system"
          "aws:RequestTag/kubernetes-service-account" = "aws-node"
        }
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-vpc-cni-pod-identity"
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni.arn

  depends_on = [
    aws_eks_addon.pre_node["eks-pod-identity-agent"],
    aws_eks_addon.pre_node["vpc-cni"],
    aws_iam_role_policy_attachment.vpc_cni,
  ]
}

# Private node subnet에서 Pod Identity Agent가 EKS Auth API에 접근하도록
# Interface VPC Endpoint를 둡니다. AWS 문서는 Private subnet 노드에 이 endpoint를 요구합니다.
resource "aws_security_group" "eks_auth_endpoint" {
  name        = "${var.name_prefix}-eks-auth-endpoint"
  description = "Allow EKS nodes to reach the EKS Auth API for Pod Identity."
  vpc_id      = var.vpc_id

  ingress {
    description     = "EKS Pod Identity Agent to EKS Auth API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  tags = {
    Name = "${var.name_prefix}-eks-auth-endpoint"
  }
}

resource "aws_vpc_endpoint" "eks_auth" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.eks-auth"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.app_private_subnet_ids
  security_group_ids  = [aws_security_group.eks_auth_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-eks-auth"
  }
}

resource "aws_eks_access_entry" "operator" {
  for_each = var.operator_access_entries

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "operator" {
  for_each = var.operator_access_entries

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.scope_type == "namespace" ? each.value.namespaces : null
  }

  # EKS requires the principal's Access Entry to exist before its policy association.
  depends_on = [aws_eks_access_entry.operator]
}

resource "aws_eks_node_group" "initial" {
  count = length(var.app_private_subnet_ids)

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-initial-workers-az-${count.index + 1}"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [var.app_private_subnet_ids[count.index]]

  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes,
    aws_eks_addon.pre_node,
    aws_eks_pod_identity_association.vpc_cni,
  ]
}

resource "aws_iam_role" "bastion" {
  name = "${var.name_prefix}-bastion-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_cloudwatch_log_group" "bastion_sessions" {
  name              = "/aws/ssm/${var.name_prefix}-bastion-sessions"
  retention_in_days = var.session_log_retention

  tags = {
    Name = "${var.name_prefix}-bastion-sessions"
  }
}

resource "aws_ssm_document" "session_preferences" {
  name            = "SSM-SessionManagerRunShell-${var.name_prefix}"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Audited SSM shell sessions for the SAI private Bastion."
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.bastion_sessions.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      runAsEnabled                = true
      runAsDefaultUser            = "sai-operator"
    }
  })
}

# 기본 AWS 원격 포트포워딩 문서는 호출자가 임의 host/port를 지정할 수 있습니다.
# 이 문서는 현재 EKS API의 443 포트와 로컬 8443 포트만 허용합니다.
resource "aws_ssm_document" "eks_api_tunnel" {
  name            = "${var.name_prefix}-eks-api-tunnel"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Port forwarding only to this cluster's private Kubernetes API."
    sessionType   = "Port"
    properties = {
      type            = "LocalPortForwarding"
      host            = trimprefix(aws_eks_cluster.main.endpoint, "https://")
      portNumber      = "443"
      localPortNumber = "8443"
    }
  })
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.app_private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/bastion-user-data.sh.tftpl", {
    cluster_version = var.cluster_version
    aws_region      = var.aws_region
    operator_users = jsonencode(distinct(concat(
      ["sai-operator"],
      [for entry in values(var.operator_access_entries) : entry.run_as_user],
    )))
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
    volume_size = 12
  }

  tags = {
    Name = "${var.name_prefix}-bastion"
  }
}

resource "aws_iam_policy" "operator_ssm" {
  name        = "${var.name_prefix}-bastion-operator-ssm"
  description = "Attach to approved human roles to start SSM Bastion shell and private EKS API forwarding sessions."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:StartSession"]
        Resource = [
          aws_instance.bastion.arn,
          aws_ssm_document.session_preferences.arn,
          aws_ssm_document.eks_api_tunnel.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = ["ssm:GetDocument"]
        Resource = [
          aws_ssm_document.session_preferences.arn,
          aws_ssm_document.eks_api_tunnel.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeInstanceInformation", "ssm:DescribeSessions"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:ResumeSession", "ssm:TerminateSession", "ssmmessages:OpenDataChannel"]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:session/$${aws:userid}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.main.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "bastion_session_logs" {
  name = "${var.name_prefix}-bastion-session-logs"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.bastion_sessions.arn}:*"
    }]
  })
}
