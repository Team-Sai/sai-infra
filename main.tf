module "network" {
  source = "./modules/network"

  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  subnet_cidrs       = var.subnet_cidrs
}

module "eks" {
  source = "./modules/eks"

  name_prefix             = local.name_prefix
  aws_region              = var.aws_region
  cluster_version         = var.eks_cluster_version
  vpc_id                  = module.network.vpc_id
  app_private_subnet_ids  = module.network.app_private_subnet_ids
  node_instance_types     = var.eks_node_instance_types
  bastion_instance_type   = "t3.micro"
  session_log_retention   = var.session_log_retention_days
  cluster_log_retention   = var.eks_control_plane_log_retention_days
  operator_access_entries = var.operator_access_entries
}

module "data" {
  source = "./modules/data"

  name_prefix                   = local.name_prefix
  vpc_id                        = module.network.vpc_id
  data_private_subnet_ids       = module.network.data_private_subnet_ids
  node_security_group_id        = module.eks.node_security_group_id
  rds_instance_class            = var.rds_instance_class
  rds_allocated_storage_gib     = var.rds_allocated_storage_gib
  rds_backup_retention_days     = var.rds_backup_retention_days
  rds_deletion_protection       = var.rds_deletion_protection
  rds_final_snapshot_identifier = var.rds_final_snapshot_identifier
  redis_node_type               = var.redis_node_type
  redis_engine_version          = var.redis_engine_version
}

module "storage" {
  source = "./modules/storage"

  name_prefix = local.name_prefix
  repositories = [
    "sai-backend",
    "sai-frontend",
    "sai-mock-bank",
    "sai-ai",
  ]
}

# Mock Bank는 첫 통합 데모에 포함하되, ECR 이미지 digest와 Secrets Manager 항목 등
# 필수 값은 기본 인프라를 준비한 뒤 전용 tfvars에서 설정해 활성화합니다. 비용이 발생합니다.
module "mock_bank" {
  count  = var.enable_mock_bank ? 1 : 0
  source = "./modules/mock-bank"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix                          = local.name_prefix
  aws_region                           = var.aws_region
  main_vpc_id                          = module.network.vpc_id
  main_vpc_cidr                        = var.vpc_cidr
  main_app_route_table_ids             = module.network.app_private_route_table_ids
  main_app_subnet_cidrs                = module.network.app_private_subnet_cidrs
  mock_bank_image                      = var.mock_bank_image_digest
  mock_bank_secret_arn                 = var.mock_bank_secret_arn
  mock_bank_api_hostname               = var.mock_bank_api_hostname
  mock_bank_api_certificate_secret_arn = var.mock_bank_api_certificate_secret_arn
  mock_bank_ecr_repository_arn         = module.storage.ecr_repository_arns["sai-mock-bank"]
  instance_type                        = var.mock_bank_instance_type
  data_volume_size_gib                 = var.mock_bank_data_volume_size_gib
  snapshot_retention_count             = var.mock_bank_snapshot_retention_count
  viewer_domain_name                   = var.mock_bank_viewer_domain_name
  viewer_certificate_arn               = var.mock_bank_viewer_certificate_arn
  public_hosted_zone_id                = var.mock_bank_public_hosted_zone_id
}

# GitHub Actions가 장기 AWS 키 없이 OIDC로 임시 자격 증명을 받아,
# 위에서 만든 ECR 저장소에만 이미지를 올리도록 역할을 구성합니다.
module "github_actions_ecr" {
  source = "./modules/github-actions-ecr"

  name_prefix                 = local.name_prefix
  github_actions_ecr_subjects = var.github_actions_ecr_subjects
  existing_oidc_provider_arn  = var.github_oidc_provider_arn
  ecr_repository_arns         = module.storage.ecr_repository_arns
}

module "iam" {
  source = "./modules/iam"

  name_prefix                              = local.name_prefix
  eks_cluster_name                         = module.eks.cluster_name
  eks_cluster_arn                          = module.eks.cluster_arn
  application_namespace                    = var.application_namespace
  application_service_account              = var.application_service_account
  load_balancer_controller_namespace       = var.load_balancer_controller_namespace
  load_balancer_controller_service_account = var.load_balancer_controller_service_account
  backup_bucket_arn                        = module.storage.backup_bucket_arn
  redis_user_arn                           = module.data.redis_user_arn
  redis_replication_group_arn              = module.data.redis_replication_group_arn
  image_updater_ecr_repository_arns = [
    module.storage.ecr_repository_arns["sai-backend"],
    module.storage.ecr_repository_arns["sai-frontend"],
  ]
}
