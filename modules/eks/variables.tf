variable "name_prefix" {
  description = "리소스 이름 접두사입니다."
  type        = string
}

variable "aws_region" {
  description = "AWS 리전입니다."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes 버전입니다."
  type        = string
}

variable "vpc_id" {
  description = "EKS 및 Bastion이 배치될 VPC ID입니다."
  type        = string
}

variable "app_private_subnet_ids" {
  description = "EKS 관리 영역과 노드가 사용할 App Private 서브넷입니다."
  type        = list(string)
}

variable "node_instance_types" {
  description = "EKS managed node group EC2 타입 목록입니다."
  type        = list(string)
}

variable "bastion_instance_type" {
  description = "Private Bastion EC2 타입입니다."
  type        = string
}

variable "session_log_retention" {
  description = "CloudWatch Logs 보존 기간(일)입니다."
  type        = number
}

variable "cluster_log_retention" {
  description = "EKS 컨트롤 플레인 로그 보존 기간(일)입니다."
  type        = number
}

variable "operator_access_entries" {
  description = "팀원이 제공하는 IAM 역할 또는 사용자 ARN과 EKS Access Policy 연결 설정입니다."
  type = map(object({
    principal_arn = string
    policy_arn    = string
    scope_type    = string
    namespaces    = optional(list(string), [])
    run_as_user   = string
  }))
}
