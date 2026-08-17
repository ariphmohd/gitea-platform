variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name identifier"
  type        = string
  default     = "gitea"
}

variable "vpc_id" {
  description = "VPC ID where RDS is deployed"
  type        = string
}

variable "database_subnet_group_name" {
  description = "Database subnet group name created in VPC module"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security Group ID of the EKS worker nodes to allow database access"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDRs to allow PostgreSQL ingress strictly from private subnets"
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "PostgreSQL engine version (16.4 is standard for PostgreSQL 16 on RDS)"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class (db.t4g.micro for Free Tier / Dev cost efficiency)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB (20 GiB for Free Tier)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage auto-scaling threshold in GiB"
  type        = number
  default     = 50
}

variable "db_name" {
  description = "Initial database name for Gitea"
  type        = string
  default     = "giteadb"
}

variable "db_username" {
  description = "Master username for PostgreSQL"
  type        = string
  default     = "gitea_admin"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment (set to false for cost savings / Free Tier)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days (1 day for AWS Free Tier eligibility)"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Enable deletion protection for production database"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying database"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
