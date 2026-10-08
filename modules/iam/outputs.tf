output "application_role_arn" {
  description = "앱 ServiceAccount Pod Identity association에 연결된 IAM 역할 ARN입니다."
  value       = aws_iam_role.application.arn
}

output "application_backup_prefix" {
  description = "앱이 읽고 쓸 수 있는 S3 object prefix입니다."
  value       = "exports/"
}

output "load_balancer_controller_role_arn" {
  description = "팀 Kubernetes 설정의 aws-load-balancer-controller ServiceAccount Pod Identity association 역할 ARN입니다."
  value       = aws_iam_role.load_balancer_controller.arn
}
