# 역할 이름 앞부분입니다. 루트에서 sai-demo를 전달합니다.
variable "name_prefix" {
  description = "IAM 역할과 정책 이름의 접두사입니다."
  type        = string
}

# 각 ECR 저장소에 이미지를 게시할 GitHub 저장소 subject입니다.
variable "github_actions_ecr_subjects" {
  description = "ECR 저장소 이름을 key로 하고, 해당 이미지 게시를 허용할 단일 GitHub OIDC subject를 value로 하는 map입니다."
  type        = map(string)

  validation {
    condition     = length(var.github_actions_ecr_subjects) > 0
    error_message = "최소 하나의 ECR 저장소별 GitHub Actions OIDC subject가 필요합니다."
  }
}

# 같은 계정에 GitHub provider가 있으면 재생성하지 않고 기존 ARN을 씁니다.
variable "existing_oidc_provider_arn" {
  description = "기존 GitHub OIDC provider ARN입니다. null이면 이 모듈이 provider를 생성합니다."
  type        = string
  default     = null
  nullable    = true
}

# 푸시 권한을 생성된 ECR 저장소로만 제한합니다.
variable "ecr_repository_arns" {
  description = "이미지 푸시를 허용할 ECR 저장소 이름별 ARN map입니다."
  type        = map(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "ECR push 역할에 하나 이상의 ECR repository ARN을 지정해야 합니다."
  }
}
