variable "name_prefix" {
  description = "Mock Bank 리소스 이름과 태그 접두사입니다."
  type        = string
}

variable "aws_region" {
  description = "Mock Bank가 배포될 AWS 리전입니다."
  type        = string
}

variable "mock_vpc_cidr" {
  description = "Mock Bank 전용 VPC CIDR입니다. 주 VPC·사내망과 겹치지 않아야 합니다."
  type        = string
  default     = "10.251.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.mock_vpc_cidr))
    error_message = "mock_vpc_cidr은 올바른 IPv4 CIDR이어야 합니다."
  }
}

variable "mock_availability_zone" {
  description = "단일 Mock Bank EC2와 EBS를 배치할 AZ입니다. 한 AZ 구성은 고가용성이 아닙니다."
  type        = string
  default     = "ap-northeast-2a"
}

variable "main_vpc_id" {
  description = "VPC Peering 상대인 SAI EKS 주 VPC ID입니다."
  type        = string
}

variable "main_vpc_cidr" {
  description = "피어링 상대인 SAI EKS 주 VPC CIDR입니다. Mock Bank VPC와 겹치면 안 됩니다."
  type        = string
}

variable "main_app_route_table_ids" {
  description = "Mock Bank 사설망 경로를 추가할 SAI App Private 라우트 테이블 ID 목록입니다."
  type        = list(string)
}

variable "main_app_subnet_cidrs" {
  description = "Mock Bank TLS API 8443을 허용할 SAI App Private 서브넷 CIDR 목록입니다."
  type        = list(string)
}

variable "mock_bank_image" {
  description = "sai-mock-bank ECR 이미지 URI입니다. 변경 가능한 tag 대신 sha256 digest로 고정합니다."
  type        = string

  validation {
    condition     = var.mock_bank_image != null && can(regex("@sha256:[0-9a-f]{64}$", var.mock_bank_image))
    error_message = "이미지는 @sha256:<64자리 digest> 형식으로 지정해야 합니다."
  }
}

variable "mock_bank_secret_arn" {
  description = "Compose 앱 비밀 설정 JSON을 보관하는 Secrets Manager ARN입니다. 비밀 값은 입력하지 않습니다."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.mock_bank_secret_arn))
    error_message = "mock_bank_secret_arn에는 실제 Secrets Manager ARN을 지정해야 합니다."
  }
}

variable "mock_bank_api_hostname" {
  description = "팀 소유 공개 도메인 아래의 사설 API 호스트 이름입니다. 인증서 SAN과 일치해야 합니다."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.mock_bank_api_hostname))
    error_message = "mock_bank_api_hostname은 소유한 FQDN으로 지정해야 합니다. 내부 전용 가상 도메인은 공인 인증서와 일치하지 않습니다."
  }
}

variable "mock_bank_api_certificate_secret_arn" {
  description = "TLS_CERTIFICATE_PEM과 TLS_PRIVATE_KEY_PEM JSON 키를 가진 Secrets Manager ARN입니다. 값은 Terraform 상태에 넣지 않습니다."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.mock_bank_api_certificate_secret_arn))
    error_message = "TLS 인증서 secret ARN을 지정해야 합니다."
  }
}

variable "mock_bank_ecr_repository_arn" {
  description = "sai-mock-bank ECR 저장소 ARN입니다. EC2 image pull 권한을 이 저장소로 제한합니다."
  type        = string
}

variable "mock_bank_api_port" {
  description = "SAI 백엔드 전용 TLS API 포트입니다."
  type        = number
  default     = 8443
}

variable "mock_bank_origin_port" {
  description = "CloudFront VPC Origin이 Mock Bank 사설 EC2 Nginx에 연결하는 HTTP 포트입니다."
  type        = number
  default     = 8080
}

variable "mock_bank_app_port" {
  description = "Compose 앱의 loopback 전용 포트입니다. 인터넷/CloudFront에서 직접 연결하지 않습니다."
  type        = number
  default     = 8081
}

variable "instance_type" {
  description = "비용이 드는 Mock Bank 단일 EC2 크기입니다. 작은 데모용 기본값이며 성능을 보장하지 않습니다."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gib" {
  description = "EC2 운영체제와 컨테이너 이미지가 저장되는 암호화 root EBS 크기입니다."
  type        = number
  default     = 30
}

variable "data_volume_size_gib" {
  description = "MariaDB 데이터를 저장할 별도 암호화 gp3 EBS 크기입니다."
  type        = number
  default     = 20

  validation {
    condition     = var.data_volume_size_gib >= 20 && var.data_volume_size_gib <= 16384
    error_message = "MariaDB EBS는 20 GiB 이상 16,384 GiB 이하여야 합니다."
  }
}

variable "snapshot_retention_count" {
  description = "DLM 일일 EBS 스냅샷 보존 개수입니다. 기본 7개이며 보관 비용이 발생합니다."
  type        = number
  default     = 7

  validation {
    condition     = var.snapshot_retention_count >= 1 && var.snapshot_retention_count <= 1000
    error_message = "스냅샷 보존 개수는 1 이상 1,000 이하여야 합니다."
  }
}

variable "docker_compose_version" {
  description = "EC2 부팅 때 설치할 Docker Compose v2 버전입니다."
  type        = string
  default     = "v2.29.7"
}

variable "docker_compose_sha256" {
  description = "Docker Compose Linux x86_64 바이너리의 고정 SHA-256 체크섬입니다. 버전 변경 시 공식 체크섬과 함께 갱신해야 합니다."
  type        = string
  default     = "383ce6698cd5d5bbf958d2c8489ed75094e34a77d340404d9f32c4ae9e12baf0"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.docker_compose_sha256))
    error_message = "Docker Compose SHA-256 체크섬은 64자리 소문자 16진수여야 합니다."
  }
}

variable "mariadb_image" {
  description = "MariaDB 공식 이미지의 digest 고정 URI입니다."
  type        = string
  default     = "mariadb@sha256:1292844148b311e4ed4300022a996d39083f415a963e970cf47cad1b3b18e3a6"

  validation {
    condition     = can(regex("^mariadb@sha256:[0-9a-f]{64}$", var.mariadb_image))
    error_message = "MariaDB 이미지는 mariadb@sha256:<64자리 digest> 형식이어야 합니다."
  }
}

variable "viewer_domain_name" {
  description = "선택형 브라우저 도메인입니다. 비워 두면 CloudFront 기본 도메인으로 HTTPS를 제공합니다."
  type        = string
  default     = null
  nullable    = true
}

variable "viewer_certificate_arn" {
  description = "선택형 사용자 도메인용 ACM 인증서 ARN입니다. us-east-1이어야 합니다."
  type        = string
  default     = null
  nullable    = true
}

variable "public_hosted_zone_id" {
  description = "선택형 브라우저 도메인 Alias 레코드를 만들 Route 53 공개 Hosted Zone ID입니다."
  type        = string
  default     = null
  nullable    = true
}
