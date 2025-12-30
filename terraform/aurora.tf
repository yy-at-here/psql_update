resource "aws_security_group" "aurora-sg" {
  name        = "aurora-sg"
  description = "security group for aurora"
  vpc_id      = aws_vpc.psql-update-vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_cluster_parameter_group" "aurora-cluster-parameter-group" {
  name        = "psql-update-cluster-parameter-group-pgsql17"
  family      = "aurora-postgresql17"
  description = "Cluster Parameter group for psql-update Aurora PostgreSQL"

  parameter {
    name  = "track_wal_io_timing"
    value = "on"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    apply_method = "immediate"
    name         = "rds.force_ssl"
    value        = "0"
  }
}

resource "aws_db_subnet_group" "aurora-subnet-group" {
  name = "psql-update-aurora-subnet-group"
  subnet_ids = [
    aws_subnet.private-subnet-aurora-a.id,
    aws_subnet.private-subnet-aurora-c.id
  ]

  tags = {
    Name = "psql-update-aurora-subnet-group"
  }
}

resource "aws_rds_cluster" "aurora-cluster" {
  cluster_identifier = "psql-update-aurora-cluster"

  # 各種グループの設定
  db_subnet_group_name            = aws_db_subnet_group.aurora-subnet-group.name
  vpc_security_group_ids          = [aws_security_group.aurora-sg.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora-cluster-parameter-group.name

  # データベースエンジン
  engine         = "aurora-postgresql"
  engine_version = "17.6"

  master_username     = "postgres"
  database_name       = "app_db"
  skip_final_snapshot = true
  deletion_protection = false # destroy時に削除を許可

  # パスワードを AWS Secrets Manager で自動管理
  manage_master_user_password = true

  # EC2 からの接続を許可
  iam_database_authentication_enabled = true
}

resource "aws_rds_cluster_instance" "aurora-instance" {
  identifier         = "psql-update-aurora-instance"
  cluster_identifier = aws_rds_cluster.aurora-cluster.id
  availability_zone  = aws_subnet.private-subnet-aurora-a.availability_zone

  # エンジン、バージョン、インスタンスタイプの設定
  instance_class    = "db.r6g.large"
  engine            = aws_rds_cluster.aurora-cluster.engine
  engine_version    = aws_rds_cluster.aurora-cluster.engine_version
  apply_immediately = true # 変更・削除を即時反映

  tags = {
    Name = "psql-update-aurora-instance-1"
  }
}
