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
  description = "MariaDB 11.4 defaults and required TLS transport for the SAI application."

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

  # TLS를 사용하지 않는 DB 연결은 RDS가 거부하도록 합니다.
  # 앱과 DB 초기화 Job도 CA 인증서를 확인하며 TLS로 연결해야 합니다.
  parameter {
    name         = "require_secure_transport"
    value        = "ON"
    apply_method = "immediate"
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

# 읽기 복제본은 쓰기 인스턴스의 비동기 복제본입니다. 두 AZ에 하나씩 두어
# 읽기 용량과 AZ 분산을 제공하지만, 앱의 읽기를 자동으로 이쪽으로 보내지는 않습니다.
resource "aws_db_instance" "mariadb_read_replica" {
  count = length(var.availability_zones)

  identifier                 = "${var.name_prefix}-mariadb-read-${count.index + 1}"
  replicate_source_db        = aws_db_instance.mariadb.arn
  instance_class             = var.rds_instance_class
  availability_zone          = var.availability_zones[count.index]
  db_subnet_group_name       = aws_db_subnet_group.main.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  publicly_accessible        = false
  deletion_protection        = var.rds_deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.rds_final_snapshot_identifier}-read-${count.index + 1}"
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.name_prefix}-mariadb-read-${count.index + 1}"
    Role = "read-replica"
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
  # RefreshTokenService와 상환 기능이 사용하는 키만 허용하고, Lua 스크립트는 EVAL/EVALSHA만 허용합니다.
  # 권한 규칙은 -@all 이후에 필요한 명령만 추가합니다.
  access_string = "on ~auth:refresh:* ~repayment:* -@all +@read +@write +@connection +eval +evalsha"

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
