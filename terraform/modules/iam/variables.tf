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

variable "oidc_provider_arn" {
  description = "The ARN of the EKS OIDC Provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "The URL of the EKS OIDC Provider (without https://)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for Gitea storage"
  type        = string
}

variable "db_password_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret for database credentials"
  type        = string
}

variable "gitea_namespace" {
  description = "Kubernetes namespace where Gitea is deployed"
  type        = string
  default     = "gitea"
}

variable "gitea_service_account_name" {
  description = "Kubernetes Service Account name for Gitea pods"
  type        = string
  default     = "gitea"
}

variable "alb_controller_namespace" {
  description = "Kubernetes namespace where AWS Load Balancer Controller is deployed"
  type        = string
  default     = "kube-system"
}

variable "alb_controller_service_account_name" {
  description = "Kubernetes Service Account name for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "efs_csi_service_account_name" {
  description = "Kubernetes Service Account name for AWS EFS CSI Driver"
  type        = string
  default     = "efs-csi-controller-sa"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
