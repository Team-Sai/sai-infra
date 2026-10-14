output "vpc_id" {
  description = "Mock Bank 전용 VPC ID입니다."
  value       = aws_vpc.mock_bank.id
}

output "instance_id" {
  description = "Docker Compose를 실행하는 단일 EC2 instance ID입니다."
  value       = aws_instance.mock_bank.id
}

output "private_ip" {
  description = "VPC 피어링 API DNS에 연결된 고정 Mock Bank EC2 private IP입니다."
  value       = aws_instance.mock_bank.private_ip
}

output "private_subnet_ids" {
  description = "Mock Bank EC2가 배치되는 사설 서브넷 ID 목록입니다."
  value       = [aws_subnet.private.id]
}

output "private_api_url" {
  description = "SAI 백엔드에서 사용할 사설 TLS API 주소입니다."
  value       = "https://${var.mock_bank_api_hostname}:${var.mock_bank_api_port}"
}

output "browser_url" {
  description = "브라우저에서 접속할 CloudFront HTTPS 주소입니다."
  value       = "https://${var.viewer_domain_name == null ? aws_cloudfront_distribution.mock_bank.domain_name : var.viewer_domain_name}"
}

output "vpc_peering_connection_id" {
  description = "주 VPC와 Mock Bank VPC 사이의 peering connection ID입니다."
  value       = aws_vpc_peering_connection.main.id
}
