output "backup_bucket_name" {
  description = "앱 백업 파일 및 export를 보관할 비공개 S3 버킷 이름입니다."
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
