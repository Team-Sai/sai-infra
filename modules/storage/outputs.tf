output "s3_bucket_name" {
  description = "앱이 file.storage=s3로 저장할 비공개 S3 버킷 이름입니다."
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "앱 Pod Identity 권한 정책에 사용하는 S3 버킷 ARN입니다."
  value       = aws_s3_bucket.backup.arn
}

output "ecr_repository_urls" {
  description = "ECR 저장소별 push/pull URL map입니다."
  value       = { for name, repository in aws_ecr_repository.application : name => repository.repository_url }
}

output "ecr_repository_arns" {
  description = "ECR 저장소별 ARN map입니다. GitHub Actions push 역할을 해당 저장소에만 제한할 때 사용합니다."
  value       = { for name, repository in aws_ecr_repository.application : name => repository.arn }
}
