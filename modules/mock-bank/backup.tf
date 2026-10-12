resource "aws_iam_role" "ebs_snapshot_lifecycle" {
  name = "${var.name_prefix}-mock-bank-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dlm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_snapshot_lifecycle" {
  role       = aws_iam_role.ebs_snapshot_lifecycle.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# 매일 03:00 UTC에 MariaDB 데이터 EBS 스냅샷을 만들고 기본 7개를 유지합니다.
# 실행 중인 DB의 EBS 스냅샷은 crash-consistent이며 DB 일관성을 보장하지 않습니다. 합성 데모 데이터만 사용하고 복원 검증을 별도로 해야 합니다.
resource "aws_dlm_lifecycle_policy" "database" {
  description        = "Daily encrypted snapshots for the synthetic Mock Bank MariaDB data volume"
  execution_role_arn = aws_iam_role.ebs_snapshot_lifecycle.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      BackupPolicy = local.data_volume_tag
    }

    schedule {
      name = "DailyMockBankDatabaseSnapshot"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = var.snapshot_retention_count
      }

      copy_tags = true
    }
  }

  depends_on = [aws_iam_role_policy_attachment.ebs_snapshot_lifecycle]
}
