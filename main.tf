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
  ]
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
  application_db_secret_arn                = module.data.application_db_secret_arn
  redis_user_arn                           = module.data.redis_user_arn
  redis_replication_group_arn              = module.data.redis_replication_group_arn

  depends_on = [module.eks]
}
