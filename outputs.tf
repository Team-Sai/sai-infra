output "vpc_id" {
  description = "주 애플리케이션 VPC ID입니다. apply 전에는 실제 ID가 없습니다."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "AZ 순서별 Public 서브넷 ID 목록입니다."
  value       = module.network.public_subnet_ids
}

output "app_private_subnet_ids" {
  description = "AZ 순서별 App Private 서브넷 ID 목록입니다."
  value       = module.network.app_private_subnet_ids
}

output "data_private_subnet_ids" {
  description = "AZ 순서별 Data Private 서브넷 ID 목록입니다."
  value       = module.network.data_private_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름입니다."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Private 전용 EKS API 주소입니다. VPC 연결 없이 접근할 수 없습니다."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "kubectl 설정에 사용하는 EKS 인증 기관 데이터입니다."
  value       = module.eks.cluster_certificate_authority_data
}

output "bastion_instance_id" {
  description = "SSM Session Manager로 접속할 Private Bastion의 인스턴스 ID입니다."
  value       = module.eks.bastion_instance_id
}

output "operator_access_role_arns" {
  description = "EKS Access Entry에 등록한 팀원 역할 ARN 목록입니다. 실제 값은 입력 변수에서 제공합니다."
  value       = module.eks.operator_access_role_arns
}

output "bastion_operator_ssm_policy_arn" {
  description = "팀원 Identity Center 역할에 연결할 Bastion 전용 SSM 정책 ARN입니다."
  value       = module.eks.operator_ssm_policy_arn
}

output "bastion_session_log_group_name" {
  description = "SSM 셸 세션 로그가 저장되는 CloudWatch Logs 그룹입니다."
  value       = module.eks.session_log_group_name
}

output "bastion_session_document_name" {
  description = "팀원이 SSM shell 접속 시 --document-name에 지정할 세션 문서 이름입니다."
  value       = module.eks.session_document_name
}

output "eks_api_tunnel_document_name" {
  description = "고정된 EKS API 호스트의 TCP 443만 전달하는 SSM 세션 문서 이름입니다."
  value       = module.eks.eks_api_tunnel_document_name
}

output "rds_endpoint" {
  description = "RDS MariaDB writer endpoint입니다. 비밀번호는 출력하지 않습니다."
  value       = module.data.rds_endpoint
}

output "rds_port" {
  description = "RDS MariaDB 포트입니다."
  value       = module.data.rds_port
}

output "rds_master_secret_arn" {
  description = "RDS가 Secrets Manager에서 관리하는 master secret ARN입니다. 암호 자체는 출력하지 않습니다."
  value       = module.data.rds_master_secret_arn
}

output "application_db_secret_arn" {
  description = "앱 DB 전용 사용자 자격 증명을 DBA가 등록할 Secrets Manager ARN입니다. secret value는 아직 없습니다."
  value       = module.data.application_db_secret_arn
}

output "redis_primary_endpoint" {
  description = "Multi-AZ Redis OSS Primary endpoint입니다."
  value       = module.data.redis_primary_endpoint
}

output "redis_reader_endpoint" {
  description = "Redis OSS reader endpoint입니다. 읽기 부하 분산용이며 primary 대체 주소가 아닙니다."
  value       = module.data.redis_reader_endpoint
}

output "redis_port" {
  description = "Redis OSS TLS 포트입니다."
  value       = module.data.redis_port
}

output "ecr_repository_urls" {
  description = "저장소 이름별 ECR URL map입니다."
  value       = module.storage.ecr_repository_urls
}

output "backup_bucket_name" {
  description = "앱 백업 파일·내보내기 파일 보관용 S3 버킷입니다. RDS 자동 백업은 이 버킷에 자동 복사되지 않습니다."
  value       = module.storage.backup_bucket_name
}

output "application_role_arns" {
  description = "앱 Kubernetes ServiceAccount의 Pod Identity association에 연결된 IAM 역할 ARN map입니다."
  value = {
    ("${var.application_namespace}/${var.application_service_account}") = module.iam.application_role_arn
  }
}

output "application_backup_prefix" {
  description = "앱이 S3 백업 파일을 저장할 prefix입니다."
  value       = module.iam.application_backup_prefix
}

output "load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller ServiceAccount의 Pod Identity association 역할 ARN입니다. Controller 설치는 별도 범위입니다."
  value       = module.iam.load_balancer_controller_role_arn
}
