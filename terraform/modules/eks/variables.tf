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

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "gitea-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  description = "VPC ID where EKS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes and internal load balancers"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 Instance types for EKS managed node group (Graviton2 ARM64)"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "ami_type" {
  description = "AMI Type for EKS node group (AL2023_ARM_64_STANDARD for Graviton on EKS 1.36)"
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

variable "node_capacity_type" {
  description = "Type of capacity associated with the EKS Node Group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Root disk size in GiB for worker nodes"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
