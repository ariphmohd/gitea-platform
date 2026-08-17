# Query AWS RDS for the default supported PostgreSQL engine version in the current region
data "aws_rds_engine_version" "postgres" {
  engine       = "postgres"
  default_only = true
}

# Random Master Password
resource "random_password" "master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for Gitea PostgreSQL RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow PostgreSQL traffic from EKS worker nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    cidr_blocks     = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : ["10.0.0.0/16"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-sg"
      Environment = var.environment
    }
  )
}

# RDS Parameter Group dynamically matched to the active PostgreSQL family
resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-pg-params"
  family      = data.aws_rds_engine_version.postgres.parameter_group_family
  description = "PostgreSQL parameter group for Gitea (${data.aws_rds_engine_version.postgres.parameter_group_family})"

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-pg-params"
      Environment = var.environment
    }
  )
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  identifier            = "${var.project_name}-${var.environment}-postgres"
  engine                = "postgres"
  engine_version        = data.aws_rds_engine_version.postgres.version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.master_password.result

  db_subnet_group_name        = var.database_subnet_group_name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  parameter_group_name        = aws_db_parameter_group.main.name
  multi_az                    = var.multi_az
  publicly_accessible         = false
  backup_retention_period     = var.backup_retention_period
  backup_window               = "03:00-04:00"
  maintenance_window          = "Mon:04:30-Mon:05:30"
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-${var.environment}-postgres-final-snapshot"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-postgres"
      Environment = var.environment
    }
  )
}

# AWS Secrets Manager Secret for Database Credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/database-credentials"
  description             = "Database credentials for Gitea application"
  recovery_window_in_days = 0

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-db-secret"
      Environment = var.environment
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.master_password.result
    endpoint = aws_db_instance.main.endpoint
  })
}
