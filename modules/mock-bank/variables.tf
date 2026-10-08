variable "name_prefix" {
  description = "Mock Bank 리소스 이름 접두사입니다."
  type        = string
}

variable "aws_region" {
  description = "AWS 리전입니다."
  type        = string
  default     = "ap-northeast-2"
}

variable "mock_vpc_cidr" {
  description = "Mock Bank 전용 VPC CIDR입니다. 주 VPC·사내망과 중첩되지 않아야 합니다."
  type        = string
  default     = "10.251.0.0/16"
}

variable "mock_availability_zone" {
  description = "Mock Bank EC2를 배치할 AZ입니다."
  type        = string
  default     = "ap-northeast-2a"
}

variable "main_vpc_id" {
  description = "피어링 상대인 EKS 주 VPC ID입니다."
  type        = string
}

variable "main_vpc_cidr" {
  description = "피어링 상대인 EKS 주 VPC CIDR입니다."
  type        = string
}

variable "main_app_route_table_ids" {
  description = "Mock Bank 경로를 추가할 EKS App Private route table ID 목록입니다."
  type        = list(string)
}

variable "main_app_subnet_cidrs" {
  description = "Mock Bank API 포트 접근을 허용할 EKS App Private subnet CIDR 목록입니다."
  type        = list(string)
}

variable "mock_bank_image" {
  description = "ECR에 게시된 Mock Bank 컨테이너 이미지의 digest 고정 URI입니다."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.mock_bank_image))
    error_message = "이미지는 변경 가능한 tag 대신 @sha256:<64자리 digest>로 고정해야 합니다."
  }
}

variable "mock_bank_secret_arn" {
  description = "Compose 환경변수를 JSON으로 보관한 Secrets Manager secret ARN입니다. secret value는 Terraform에 입력하지 않습니다."
  type        = string
}

variable "mock_bank_api_port" {
  description = "Mock Bank 앱 포트입니다. 현재 Dockerfile의 기본 포트는 8081입니다."
  type        = number
  default     = 8081
}

variable "instance_type" {
  description = "선택형 Mock Bank EC2 타입입니다. 비용·용량을 직접 확인하세요."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gib" {
  description = "Mock Bank EC2 암호화 root EBS 크기(GB)입니다."
  type        = number
  default     = 30
}

variable "docker_compose_version" {
  description = "EC2 부팅 시 설치할 Docker Compose v2 버전입니다."
  type        = string
  default     = "v2.29.7"
}
