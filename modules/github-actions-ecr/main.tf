locals {
  oidc_issuer_url = "https://token.actions.githubusercontent.com"
  oidc_issuer     = "token.actions.githubusercontent.com"

  # 기존 provider ARN을 받지 않았을 때만 새로 만든 provider ARN을 사용합니다.
  oidc_provider_arn = var.existing_oidc_provider_arn != null ? var.existing_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
}

# GitHub Actions가 AWS STS에 OIDC 토큰을 제시할 수 있도록 등록합니다.
# 이미 계정에 같은 provider가 있으면 루트 입력값으로 기존 ARN을 전달해 중복 생성을 피합니다.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_oidc_provider_arn == null ? 1 : 0

  url            = local.oidc_issuer_url
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "${var.name_prefix}-github-actions-oidc"
  }
}

# ECR 저장소마다 IAM 역할을 따로 만들어, 각 GitHub 저장소가 자기 이미지에만 접근하도록 합니다.
data "aws_iam_policy_document" "github_actions_assume_role" {
  for_each = var.github_actions_ecr_subjects

  statement {
    sid     = "GitHubActionsFromApprovedMainBranch"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr_push" {
  for_each = var.github_actions_ecr_subjects

  name               = "${var.name_prefix}-github-ecr-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[each.key].json

  tags = {
    Name           = "${var.name_prefix}-github-ecr-${each.key}"
    ECRRepository  = each.key
    GitHubWorkflow = each.value
  }
}

# ECR 로그인 토큰 발급에는 Resource "*"가 필요하지만,
# 실제 이미지 업로드 동작은 해당 역할에 연결된 ECR 저장소 ARN 하나로 한정합니다.
data "aws_iam_policy_document" "ecr_push_only" {
  for_each = var.github_actions_ecr_subjects

  statement {
    sid       = "GetEcrAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushImagesToConfiguredRepositories"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arns[each.key]]
  }

  statement {
    sid       = "CheckImagesInConfiguredRepositories"
    effect    = "Allow"
    actions   = ["ecr:DescribeImages"]
    resources = [var.ecr_repository_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "ecr_push_only" {
  for_each = var.github_actions_ecr_subjects

  name   = "${var.name_prefix}-github-ecr-${each.key}"
  role   = aws_iam_role.github_actions_ecr_push[each.key].id
  policy = data.aws_iam_policy_document.ecr_push_only[each.key].json
}
