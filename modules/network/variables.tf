variable "name_prefix" {
  description = "리소스 이름 접두사입니다."
  type        = string
}

variable "aws_region" {
  description = "AWS 리전입니다."
  type        = string
}

variable "vpc_cidr" {
  description = "주 VPC IPv4 CIDR입니다."
  type        = string
}

variable "availability_zones" {
  description = "각 서브넷 역할을 배치할 AZ 목록입니다."
  type        = list(string)
}

variable "subnet_cidrs" {
  description = "Public, App Private, Data Private 각 AZ별 CIDR 목록입니다."
  type = object({
    public = list(string)
    app    = list(string)
    data   = list(string)
  })

  validation {
    condition     = length(var.subnet_cidrs.public) == 2 && length(var.subnet_cidrs.app) == 2 && length(var.subnet_cidrs.data) == 2
    error_message = "각 서브넷 역할에는 AZ별 CIDR 두 개가 필요합니다."
  }
}
