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
  description = "VPC ID where EFS is deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDRs to allow NFS ingress strictly from private subnets"
  type        = list(string)
  default     = []
}

variable "availability_zone_name" {
  description = "Availability Zone name for EFS One Zone deployment (e.g. ap-south-1a to save cost)"
  type        = string
  default     = "ap-south-1a"
}

variable "enable_one_zone" {
  description = "Enable EFS One Zone for ~50% storage cost savings"
  type        = bool
  default     = true
}

variable "eks_node_security_group_id" {
  description = "Security Group ID of the EKS worker nodes to allow NFS access"
  type        = string
}

variable "enable_efs_backup" {
  description = "Enable automatic backup policy for EFS"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
