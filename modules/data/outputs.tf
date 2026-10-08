output "rds_endpoint" {
  description = "MariaDB writer endpoint입니다."
  value       = aws_db_instance.mariadb.address
}

output "rds_port" {
  description = "MariaDB 접속 포트입니다."
  value       = aws_db_instance.mariadb.port
}

output "rds_master_secret_arn" {
  description = "RDS가 Secrets Manager에서 관리하는 master secret ARN입니다."
  value       = aws_db_instance.mariadb.master_user_secret[0].secret_arn
}

output "application_db_secret_arn" {
  description = "빈 secret container ARN입니다. DBA는 앱 DB 계정을 만든 뒤 별도 절차로 secret version을 등록해야 합니다."
  value       = aws_secretsmanager_secret.application_db.arn
}

output "redis_primary_endpoint" {
  description = "Redis Primary endpoint입니다."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint입니다."
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "redis_port" {
  description = "Redis TLS port입니다."
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_user_arn" {
  description = "IAM 인증에 사용하는 ElastiCache User ARN입니다."
  value       = aws_elasticache_user.application.arn
}

output "redis_replication_group_arn" {
  description = "앱 IAM 정책에서 Connect 권한을 제한할 Redis replication group ARN입니다."
  value       = aws_elasticache_replication_group.redis.arn
}
