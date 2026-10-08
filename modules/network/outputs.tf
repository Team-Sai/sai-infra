output "vpc_id" {
  description = "주 애플리케이션 VPC ID입니다."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "AZ 순서별 Public 서브넷 ID입니다."
  value       = aws_subnet.public[*].id
}

output "app_private_subnet_ids" {
  description = "AZ 순서별 App Private 서브넷 ID입니다."
  value       = aws_subnet.app[*].id
}

output "app_private_route_table_ids" {
  description = "선택형 Mock Bank 피어링 경로 추가에 사용하는 App Private route table ID입니다."
  value       = aws_route_table.app[*].id
}

output "app_private_subnet_cidrs" {
  description = "Mock Bank 보안 그룹의 소스 제한에 사용할 App Private CIDR입니다."
  value       = aws_subnet.app[*].cidr_block
}

output "data_private_subnet_ids" {
  description = "AZ 순서별 Data Private 서브넷 ID입니다."
  value       = aws_subnet.data[*].id
}

output "data_private_route_table_ids" {
  description = "Data Private route table ID입니다. 외부 기본 경로는 없습니다."
  value       = aws_route_table.data[*].id
}
