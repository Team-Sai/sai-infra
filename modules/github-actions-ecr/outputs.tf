output "role_arns" {
  description = "ECR 저장소 이름별 GitHub Actions 역할 ARN map입니다. 저장소마다 해당 항목만 사용하세요."
  value       = { for repository, role in aws_iam_role.github_actions_ecr_push : repository => role.arn }
}

output "oidc_provider_arn" {
  description = "새로 생성했거나 입력받은 GitHub OIDC provider ARN입니다."
  value       = local.oidc_provider_arn
}
