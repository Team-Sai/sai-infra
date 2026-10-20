output "vpc_id" {
  description = "Mock Bank 전용 VPC ID입니다."
  value       = aws_vpc.mock_bank.id
}

output "instance_id" {
  description = "기존 출력 호환용 WAS EC2 instance ID입니다."
  value       = aws_instance.was.id
}

output "private_ip" {
  description = "기존 출력 호환용 사설 API DNS가 가리키는 WAS private IP입니다."
  value       = aws_instance.was.private_ip
}

output "private_subnet_ids" {
  description = "Mock Bank Web, WAS, Database tier의 사설 서브넷 ID입니다."
  value       = [aws_subnet.web.id, aws_subnet.was.id, aws_subnet.database.id]
}

output "web_instance_id" {
  description = "CloudFront VPC Origin의 브라우저 요청을 받는 Web EC2 instance ID입니다."
  value       = aws_instance.web.id
}

output "web_private_ip" {
  description = "Web tier Nginx의 private IP입니다."
  value       = aws_instance.web.private_ip
}

output "was_instance_id" {
  description = "Spring 애플리케이션과 SAI TLS API 프록시를 실행하는 WAS EC2 instance ID입니다."
  value       = aws_instance.was.id
}

output "was_private_ip" {
  description = "VPC 피어링 사설 API DNS가 가리키는 WAS private IP입니다."
  value       = aws_instance.was.private_ip
}

output "database_instance_id" {
  description = "MariaDB와 기존 암호화 EBS 데이터 볼륨을 사용하는 Database EC2 instance ID입니다."
  value       = aws_instance.database.id
}

output "database_private_ip" {
  description = "WAS만 접근할 수 있는 Database private IP입니다."
  value       = aws_instance.database.private_ip
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
