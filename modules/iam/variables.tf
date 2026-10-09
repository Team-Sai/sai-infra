variable "name_prefix" {
  description = "IAM 이름 접두사입니다."
  type        = string
}

variable "eks_cluster_name" {
  description = "Pod Identity association을 만들 EKS 클러스터 이름입니다."
  type        = string
}

variable "eks_cluster_arn" {
  description = "Pod Identity IAM trust policy에서 접근을 허용할 EKS 클러스터 ARN입니다."
  type        = string
}

variable "application_namespace" {
  description = "앱 Kubernetes Namespace 이름입니다."
  type        = string
}

variable "application_service_account" {
  description = "Pod Identity에 연결할 앱 ServiceAccount 이름입니다."
  type        = string
}

variable "load_balancer_controller_namespace" {
  description = "AWS Load Balancer Controller ServiceAccount Namespace입니다."
  type        = string
}

variable "load_balancer_controller_service_account" {
  description = "AWS Load Balancer Controller Pod Identity association에 사용할 ServiceAccount 이름입니다."
  type        = string
}

variable "backup_bucket_arn" {
  description = "앱 백업 버킷 ARN입니다."
  type        = string
}

variable "application_db_secret_arn" {
  description = "앱 DB 전용 자격 증명을 보관할 Secrets Manager ARN입니다."
  type        = string
}

variable "redis_user_arn" {
  description = "ElastiCache IAM user ARN입니다."
  type        = string
}

variable "redis_replication_group_arn" {
  description = "앱이 연결할 ElastiCache replication group ARN입니다."
  type        = string
}
