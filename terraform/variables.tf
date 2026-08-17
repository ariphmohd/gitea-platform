variable "aws_region" {
  description = "The AWS Region to deploy resources into"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project identifier used in naming resources"
  type        = string
  default     = "gitea"
}

# ------------------------------------------------------------------------------
# VPC Variables (2 AZs for Cost Optimization)
# ------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones in the region (2 AZs to save NAT/EKS cost)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (1 per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS nodes & EFS - 1 per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets (RDS - 1 per AZ)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ------------------------------------------------------------------------------
# EKS Variables (Graviton2 t4g.small ARM64 with AL2_ARM_64)
# ------------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS Cluster name"
  type        = string
  default     = "gitea-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  description = "Worker node instance types"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "ami_type" {
  description = "AMI type for worker nodes (AL2023_ARM_64_STANDARD for Graviton on EKS 1.36)"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

# ------------------------------------------------------------------------------
# RDS PostgreSQL Variables (Free Tier & Dev Sized)
# ------------------------------------------------------------------------------

variable "db_instance_class" {
  description = "Instance class for RDS PostgreSQL (db.t4g.micro for Free Tier / Cost Saving)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for PostgreSQL in GiB (20 GiB Free Tier)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Max auto-scaling storage in GiB"
  type        = number
  default     = 50
}

variable "db_name" {
  description = "Database name for Gitea"
  type        = string
  default     = "giteadb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "gitea_admin"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ RDS deployment (false to save cost / Free Tier)"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days (1 day for Free Tier)"
  type        = number
  default     = 1
}

variable "db_engine_version" {
  description = "PostgreSQL engine version for RDS"
  type        = string
  default     = "16.4"
}

# ------------------------------------------------------------------------------
# EFS Storage Variables (One Zone Cost Optimization)
# ------------------------------------------------------------------------------

variable "enable_efs_one_zone" {
  description = "Enable EFS One Zone deployment for ~50% cost savings"
  type        = bool
  default     = true
}

variable "efs_availability_zone" {
  description = "Primary AZ for EFS One Zone deployment"
  type        = string
  default     = "ap-south-1a"
}

# ------------------------------------------------------------------------------
# ArgoCD GitOps
# ------------------------------------------------------------------------------

variable "enable_argocd" {
  description = "Deploy ArgoCD to EKS for GitOps management"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Ingress & Domain Variables
# ------------------------------------------------------------------------------

variable "gitea_domain" {
  description = "Domain name for Gitea web interface (e.g. git.example.com)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "AWS ACM Certificate ARN for HTTPS termination (leave blank if not using ACM)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# General Tags
# ------------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to all infrastructure resources"
  type        = map(string)
  default = {
    Environment = "prod"
    Application = "gitea"
    Owner       = "Dev-Team"
    ManagedBy   = "Terraform"
  }
}
