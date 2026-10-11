variable "name_prefix" {
  description = "리소스 이름 접두사입니다."
  type        = string
}

variable "vpc_id" {
  description = "RDS와 Redis가 위치하는 주 VPC ID입니다."
  type        = string
}

variable "data_private_subnet_ids" {
  description = "두 AZ의 Data Private 서브넷입니다."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "DB/Redis 포트 접근을 허용할 EKS node SG입니다. 이를 공유하는 모든 Pod/프로세스가 네트워크 접속을 시도할 수 있으며 Pod 단위 정책은 Kubernetes 팀이 별도 구성해야 합니다."
  type        = string
}

variable "rds_instance_class" {
  description = "MariaDB RDS 인스턴스 클래스입니다."
  type        = string
}

variable "rds_allocated_storage_gib" {
  description = "RDS 초기 스토리지 크기(GB)입니다."
  type        = number
}

variable "rds_backup_retention_days" {
  description = "RDS 관리 자동 백업 보존 기간(일)입니다."
  type        = number
}

variable "rds_deletion_protection" {
  description = "RDS 삭제 보호 여부입니다."
  type        = bool
}

variable "rds_final_snapshot_identifier" {
  description = "RDS final snapshot name입니다."
  type        = string
}

variable "redis_node_type" {
  description = "Multi-AZ Redis OSS 복제 그룹의 Primary/Replica 타입입니다."
  type        = string
}

variable "redis_engine_version" {
  description = "IAM 인증을 지원하는 Redis OSS 7 이상 엔진 버전입니다."
  type        = string
}
