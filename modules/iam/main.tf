resource "aws_iam_role" "application" {
  name = "${var.name_prefix}-application-pod-identity"

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
          "aws:RequestTag/eks-cluster-arn"            = var.eks_cluster_arn
          "aws:RequestTag/kubernetes-namespace"       = var.application_namespace
          "aws:RequestTag/kubernetes-service-account" = var.application_service_account
        }
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-application-pod-identity"
  }
}

resource "aws_iam_policy" "application" {
  name        = "${var.name_prefix}-application-data-access"
  description = "App pod access to its S3 backup prefix and IAM-authenticated Redis user."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBackupBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.backup_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["exports", "exports/*"]
          }
        }
      },
      {
        Sid    = "ManageApplicationBackupObjects"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${var.backup_bucket_arn}/exports/*"
      },
      {
        Sid      = "ReadApplicationDatabaseSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.application_db_secret_arn
      },
      {
        Sid      = "ConnectToRedisAsApplicationUser"
        Effect   = "Allow"
        Action   = ["elasticache:Connect"]
        Resource = [var.redis_replication_group_arn, var.redis_user_arn]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "application" {
  role       = aws_iam_role.application.name
  policy_arn = aws_iam_policy.application.arn
}

resource "aws_eks_pod_identity_association" "application" {
  cluster_name    = var.eks_cluster_name
  namespace       = var.application_namespace
  service_account = var.application_service_account
  role_arn        = aws_iam_role.application.arn
}

# IAM 역할과 Pod Identity association은 Terraform이 관리합니다.
# Controller 설치 및 ServiceAccount manifest는 팀 Kubernetes 범위입니다.
resource "aws_iam_role" "load_balancer_controller" {
  name = "${var.name_prefix}-aws-load-balancer-controller"

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
          "aws:RequestTag/eks-cluster-arn"            = var.eks_cluster_arn
          "aws:RequestTag/kubernetes-namespace"       = var.load_balancer_controller_namespace
          "aws:RequestTag/kubernetes-service-account" = var.load_balancer_controller_service_account
        }
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-aws-load-balancer-controller"
  }
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${var.name_prefix}-aws-load-balancer-controller"
  description = "Upstream v2.14.1 policy with EC2 security-group writes restricted to this cluster-tagged groups."
  policy      = file("${path.module}/aws-load-balancer-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = var.eks_cluster_name
  namespace       = var.load_balancer_controller_namespace
  service_account = var.load_balancer_controller_service_account
  role_arn        = aws_iam_role.load_balancer_controller.arn
}
