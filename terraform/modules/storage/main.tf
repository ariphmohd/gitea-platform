# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.environment}-efs-sg"
  description = "Security group for Gitea EFS file system"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow NFS traffic from EKS worker nodes"
    from_port       = 2049
    to_port         = 2049
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
      Name        = "${var.project_name}-${var.environment}-efs-sg"
      Environment = var.environment
    }
  )
}

# AWS EFS File System (Supports One Zone for cost optimization)
resource "aws_efs_file_system" "main" {
  creation_token         = "${var.project_name}-${var.environment}-efs"
  performance_mode       = "generalPurpose"
  throughput_mode        = "bursting"
  encrypted              = true
  availability_zone_name = var.enable_one_zone ? var.availability_zone_name : null

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-efs"
      Environment = var.environment
    }
  )
}

# EFS Mount Targets (Single mount target for One Zone, or multi-AZ if disabled)
resource "aws_efs_mount_target" "main" {
  count           = var.enable_one_zone ? 1 : length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point (Gitea runs as UID 1000, GID 1000)
resource "aws_efs_access_point" "gitea" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/gitea-data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-efs-ap"
      Environment = var.environment
    }
  )
}

# EFS Backup Policy
resource "aws_efs_backup_policy" "policy" {
  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = var.enable_efs_backup ? "ENABLED" : "DISABLED"
  }
}

# S3 Bucket for Gitea Object Storage (LFS, Packages, Avatars, Attachments, Backups)
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "gitea_storage" {
  bucket        = "${var.project_name}-${var.environment}-storage-${random_id.bucket_suffix.hex}"
  force_destroy = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-storage"
      Environment = var.environment
    }
  )
}

resource "aws_s3_bucket_versioning" "gitea_storage" {
  bucket = aws_s3_bucket.gitea_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitea_storage" {
  bucket = aws_s3_bucket.gitea_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "gitea_storage" {
  bucket = aws_s3_bucket.gitea_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "gitea_storage" {
  bucket = aws_s3_bucket.gitea_storage.id

  rule {
    id     = "transition-noncurrent-to-ia"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
