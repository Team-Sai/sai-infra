variable "name_prefix" {
  description = "스토리지 이름 접두사입니다."
  type        = string
}

variable "repositories" {
  description = "생성할 ECR 저장소 이름 목록입니다."
  type        = set(string)
}
