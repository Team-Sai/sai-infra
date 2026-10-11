output "cluster_name" {
  description = "EKS 클러스터 이름입니다."
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "Pod Identity 역할 신뢰 정책을 특정 EKS 클러스터로 제한하는 ARN입니다."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Private 전용 EKS API 주소입니다."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "kubectl 설정에 사용하는 EKS 인증 기관 데이터입니다."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_security_group_id" {
  description = "DB·Redis 인바운드를 허용할 EKS node security group ID입니다."
  value       = aws_security_group.nodes.id
}

output "bastion_instance_id" {
  description = "SSM Session Manager로 연결하는 Private Bastion instance ID입니다."
  value       = aws_instance.bastion.id
}

output "session_log_group_name" {
  description = "SSM 대화형 셸 세션 CloudWatch Logs 그룹 이름입니다."
  value       = aws_cloudwatch_log_group.bastion_sessions.name
}

output "operator_ssm_policy_arn" {
  description = "승인된 운영자 역할에 연결할 Bastion SSM 및 EKS cluster discovery 정책 ARN입니다."
  value       = aws_iam_policy.operator_ssm.arn
}

output "operator_access_principal_arns" {
  description = "EKS Access Entry에 등록된 IAM 역할 또는 사용자 principal ARN입니다."
  value       = [for entry in aws_eks_access_entry.operator : entry.principal_arn]
}

output "cluster_log_group_name" {
  description = "보존 기간이 설정된 EKS 컨트롤 플레인 CloudWatch Logs 그룹입니다."
  value       = aws_cloudwatch_log_group.cluster.name
}

output "session_document_name" {
  description = "SSM 셸 세션에 사용할 CloudWatch 기록 및 RunAs 설정 문서 이름입니다."
  value       = aws_ssm_document.session_preferences.name
}

output "eks_api_tunnel_document_name" {
  description = "EKS API의 443 포트로만 연결되는 제한된 SSM 터널 문서 이름입니다."
  value       = aws_ssm_document.eks_api_tunnel.name
}
