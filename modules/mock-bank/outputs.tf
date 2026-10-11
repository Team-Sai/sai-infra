output "mock_bank_vpc_id" {
  description = "Mock Bank 전용 VPC ID입니다."
  value       = aws_vpc.mock_bank.id
}

output "mock_bank_instance_id" {
  description = "Docker Compose를 실행하는 단일 EC2 instance ID입니다."
  value       = aws_instance.mock_bank.id
}

output "mock_bank_private_ip" {
  description = "VPC 피어링을 통해 EKS 앱에서 접근할 Mock Bank private IP입니다."
  value       = aws_instance.mock_bank.private_ip
}

output "mock_bank_base_url" {
  description = "EKS 앱에서 설정할 Mock Bank 내부 URL입니다."
  value       = "http://${aws_instance.mock_bank.private_ip}:${var.mock_bank_api_port}"
}

output "vpc_peering_connection_id" {
  description = "주 VPC와 Mock Bank VPC 사이의 peering connection ID입니다."
  value       = aws_vpc_peering_connection.main.id
}
