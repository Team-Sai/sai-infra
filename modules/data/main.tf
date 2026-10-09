resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "MariaDB access from ENIs using the EKS node security group; not Pod-level isolation."
  vpc_id      = var.vpc_id

  ingress {
    description     = "MariaDB from workloads sharing the EKS node security group"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress = []

  tags = {
    Name = "${var.name_prefix}-rds"
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis"
  description = "Redis TLS access from ENIs using the EKS node security group; not Pod-level isolation."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis TLS from workloads sharing the EKS node security group"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress = []

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.data_private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnets"
  }
}

resource "aws_db_parameter_group" "mariadb" {
  name        = "${var.name_prefix}-mariadb-11-4"
  family      = "mariadb11.4"
  description = "MariaDB 11.4 server defaults for the SAI application."

  parameter {
    name         = "character_set_server"
    value        = "utf8mb4"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "collation_server"
    value        = "utf8mb4_unicode_ci"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.name_prefix}-mariadb-11-4"
  }
}

resource "aws_db_instance" "mariadb" {
  identifier                  = "${var.name_prefix}-mariadb"
  engine                      = "mariadb"
  engine_version              = "11.4"
  instance_class              = var.rds_instance_class
  allocated_storage           = var.rds_allocated_storage_gib
  max_allocated_storage       = max(var.rds_allocated_storage_gib * 2, 100)
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "sai"
  username                    = "sai_master"
  manage_master_user_password = true
  multi_az                    = true
  publicly_accessible         = false
  db_subnet_group_name        = aws_db_subnet_group.main.name
  parameter_group_name        = aws_db_parameter_group.mariadb.name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  backup_retention_period     = var.rds_backup_retention_days
  backup_window               = "18:00-18:30"
  maintenance_window          = "sun:19:00-sun:20:00"
  deletion_protection         = var.rds_deletion_protection
  copy_tags_to_snapshot       = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = var.rds_final_snapshot_identifier
  auto_minor_version_upgrade  = true

  tags = {
    Name = "${var.name_prefix}-mariadb"
  }
}

resource "aws_secretsmanager_secret" "application_db" {
  name                    = "${var.name_prefix}/database/application"
  description             = "App-only MariaDB username and password. DBA must add a secret version after creating a least-privilege DB user."
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.name_prefix}-application-db-credentials"
    DataPurpose = "Application database credentials"
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name_prefix}-redis-subnets"
  subnet_ids = var.data_private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-redis-subnets"
  }
}

resource "aws_elasticache_user" "default_disabled" {
  user_id       = "${var.name_prefix}-default-disabled"
  user_name     = "default"
  engine        = "redis"
  access_string = "off ~* -@all"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user" "application" {
  user_id   = "${var.name_prefix}-application"
  user_name = "${var.name_prefix}-application"
  engine    = "redis"
  # Backend RefreshTokenService uses auth:refresh:{userId} as its Redis key.
  access_string = "on ~auth:refresh:* -@all +@read +@write +@connection"

  authentication_mode {
    type = "iam"
  }
}

resource "aws_elasticache_user_group" "redis" {
  engine        = "redis"
  user_group_id = "${var.name_prefix}-redis-users"
  user_ids = [
    aws_elasticache_user.default_disabled.user_id,
    aws_elasticache_user.application.user_id,
  ]
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.name_prefix}-redis"
  description                = "SAI Redis OSS Multi-AZ replication group."
  engine                     = "redis"
  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true
  port                       = 6379
  parameter_group_name       = "default.redis7"
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  user_group_ids             = [aws_elasticache_user_group.redis.user_group_id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}
