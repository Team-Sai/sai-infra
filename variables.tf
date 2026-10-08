variable "aws_region" {
  description = "AWS 리전. 기본값은 서울 리전입니다."
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름과 태그에 사용하는 프로젝트 식별자입니다."
  type        = string
  default     = "sai"
}

variable "environment" {
  description = "환경 구분값입니다. 실제 팀 환경에 맞게 변경하세요."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "주 애플리케이션 VPC의 IPv4 CIDR입니다. 다른 사내망과 겹치지 않는지 확인하세요."
  type        = string
  default     = "10.250.0.0/16"
}

variable "subnet_cidrs" {
  description = "AZ 순서별 Public/App Private/Data Private CIDR입니다. vpc_cidr 안에 있고 서로 겹치지 않는지 확인하세요."
  type = object({
    public = list(string)
    app    = list(string)
    data   = list(string)
  })

  default = {
    public = ["10.250.1.0/24", "10.250.11.0/24"]
    app    = ["10.250.2.0/24", "10.250.12.0/24"]
    data   = ["10.250.3.0/24", "10.250.13.0/24"]
  }

  validation {
    condition = alltrue([
      length(var.subnet_cidrs.public) == 2,
      length(var.subnet_cidrs.app) == 2,
      length(var.subnet_cidrs.data) == 2,
    ])
    error_message = "각 서브넷 역할의 CIDR 개수는 availability_zones 개수와 같아야 합니다."
  }

  validation {
    condition = alltrue([
      for cidr in concat(var.subnet_cidrs.public, var.subnet_cidrs.app, var.subnet_cidrs.data) :
      can(cidrnetmask(cidr))
    ])
    error_message = "각 서브넷 CIDR은 유효한 IPv4 CIDR이어야 합니다. 주 VPC 범위 내 포함 여부는 별도로 확인하세요."
  }

  validation {
    condition = length(distinct(concat(
      var.subnet_cidrs.public,
      var.subnet_cidrs.app,
      var.subnet_cidrs.data,
    ))) == length(var.subnet_cidrs.public) + length(var.subnet_cidrs.app) + length(var.subnet_cidrs.data)
    error_message = "각 서브넷 CIDR은 서로 다른 값을 사용해야 합니다. CIDR 범위끼리 겹치지 않는지도 확인하세요."
  }
}

variable "availability_zones" {
  description = "사용할 서울 리전 AZ 두 개입니다. 계정별 AZ 매핑을 확인하세요."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]

  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "availability_zones에는 서로 다른 AZ 두 개를 지정해야 합니다."
  }
}

variable "eks_cluster_version" {
  description = "EKS Kubernetes 버전입니다. AWS의 지원 버전과 애드온 호환성을 확인하세요."
  type        = string
  default     = "1.35"
}

variable "eks_node_instance_types" {
  description = "초기 EKS 노드의 EC2 타입입니다. 작은 개발용 기본값이며 용량을 보장하지 않습니다."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "rds_instance_class" {
  description = "MariaDB RDS 인스턴스 클래스입니다. Multi-AZ 비용을 별도로 산정하세요."
  type        = string
  default     = "db.t3.small"
}

variable "rds_allocated_storage_gib" {
  description = "RDS 초기 할당 스토리지(GB)입니다."
  type        = number
  default     = 20
}

variable "rds_backup_retention_days" {
  description = "RDS 자동 백업 보존 일수입니다. RDS가 관리하며 S3 버킷 output과는 별개입니다."
  type        = number
  default     = 7

  validation {
    condition     = var.rds_backup_retention_days >= 1 && var.rds_backup_retention_days <= 35
    error_message = "RDS 자동 백업 보존 기간은 1일 이상 35일 이하여야 합니다."
  }
}

variable "rds_deletion_protection" {
  description = "실수로 RDS가 삭제되지 않도록 보호합니다. 폐기 전에는 계획된 절차로 해제해야 합니다."
  type        = bool
  default     = true
}

variable "rds_final_snapshot_identifier" {
  description = "RDS를 의도적으로 삭제할 때 사용할 고유 final snapshot 이름입니다. 다음 삭제 전 변경하세요."
  type        = string
  default     = "sai-dev-mariadb-final-001"
}

variable "redis_node_type" {
  description = "Redis OSS 복제 그룹 노드 타입입니다. Multi-AZ 목표에는 Primary와 Replica 두 노드가 필요합니다."
  type        = string
  default     = "cache.t3.small"
}

variable "redis_engine_version" {
  description = "IAM 인증 지원을 위해 Redis OSS 7 이상 버전을 사용합니다. 리전 지원 여부를 확인하세요."
  type        = string
  default     = "7.1"
}

variable "application_namespace" {
  description = "앱 팀이 Kubernetes YAML에서 사용할 Namespace 이름입니다."
  type        = string
  default     = "sai"
}

variable "application_service_account" {
  description = "앱 팀이 Kubernetes YAML에서 사용할 ServiceAccount 이름입니다."
  type        = string
  default     = "sai-api"
}

variable "load_balancer_controller_namespace" {
  description = "AWS Load Balancer Controller ServiceAccount Namespace입니다."
  type        = string
  default     = "kube-system"
}

variable "load_balancer_controller_service_account" {
  description = "AWS Load Balancer Controller ServiceAccount 이름입니다. Helm chart 설정과 맞춰야 합니다."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "operator_access_entries" {
  description = "팀원 IAM 역할별 EKS 권한입니다. 역할 ARN은 실제 팀 계정 값으로 채우고 필요한 권한만 부여하세요."
  type = map(object({
    role_arn    = string
    policy_arn  = string
    scope_type  = string
    namespaces  = optional(list(string), [])
    run_as_user = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for entry in values(var.operator_access_entries) : contains(["cluster", "namespace"], entry.scope_type)
    ])
    error_message = "operator_access_entries.scope_type은 cluster 또는 namespace여야 합니다."
  }

  validation {
    condition = alltrue([
      for entry in values(var.operator_access_entries) : entry.scope_type != "namespace" || length(entry.namespaces) > 0
    ])
    error_message = "scope_type이 namespace이면 namespaces에 하나 이상의 Namespace를 지정해야 합니다."
  }

  validation {
    condition = alltrue([
      for entry in values(var.operator_access_entries) : can(regex("^[a-z_][a-z0-9_-]{0,31}$", entry.run_as_user))
    ])
    error_message = "run_as_user는 소문자, 숫자, 밑줄, 하이픈으로 된 Linux 사용자 이름이어야 합니다."
  }

  validation {
    condition = length(distinct([
      for entry in values(var.operator_access_entries) : entry.run_as_user
    ])) == length(var.operator_access_entries)
    error_message = "각 operator_access_entries에는 서로 다른 run_as_user 값을 지정해야 합니다."
  }
}

variable "session_log_retention_days" {
  description = "Bastion SSM 셸 세션 CloudWatch Logs 보존 기간입니다. 로그 수집·보관 비용이 발생합니다."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.session_log_retention_days)
    error_message = "CloudWatch Logs retention에는 AWS에서 지원하는 보존 기간을 지정해야 합니다."
  }
}
