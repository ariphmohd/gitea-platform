output "configure_kubectl" {
  description = "Command to configure kubectl to connect to the new EKS cluster"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS Cluster Control Plane API Endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS Cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "rds_endpoint" {
  description = "PostgreSQL RDS connection endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "PostgreSQL RDS host address"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "PostgreSQL RDS port"
  value       = module.rds.db_instance_port
}

output "rds_database_name" {
  description = "Database name"
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "AWS Secrets Manager Secret ARN storing database credentials"
  value       = module.rds.db_password_secret_arn
}

output "s3_bucket_name" {
  description = "Amazon S3 bucket name for Gitea storage (LFS, Packages, Avatars, Backups)"
  value       = module.storage.s3_bucket_name
}

output "efs_file_system_id" {
  description = "Amazon EFS File System ID for Gitea data mount"
  value       = module.storage.efs_file_system_id
}

output "efs_access_point_id" {
  description = "Amazon EFS Access Point ID for Gitea"
  value       = module.storage.efs_access_point_id
}

output "gitea_irsa_role_arn" {
  description = "IAM Role ARN for Gitea ServiceAccount (IRSA for S3 and Secrets Manager)"
  value       = module.iam.gitea_irsa_role_arn
}

output "alb_controller_irsa_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = module.iam.alb_controller_irsa_role_arn
}

output "efs_csi_irsa_role_arn" {
  description = "IAM Role ARN for AWS EFS CSI Driver"
  value       = module.iam.efs_csi_irsa_role_arn
}

output "argocd_admin_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
}

output "argocd_port_forward_command" {
  description = "Command to port-forward ArgoCD server to http://localhost:8080"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:80"
}

# ------------------------------------------------------------------------------
# Amazon ECR Outputs (Story 1)
# ------------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "The URL of the Amazon ECR repository"
  value       = var.enable_ecr ? module.ecr[0].repository_url : ""
}

output "ecr_repository_arn" {
  description = "The ARN of the Amazon ECR repository"
  value       = var.enable_ecr ? module.ecr[0].repository_arn : ""
}

output "ecr_repository_name" {
  description = "The name of the Amazon ECR repository"
  value       = var.enable_ecr ? module.ecr[0].repository_name : ""
}

# ------------------------------------------------------------------------------
# GitHub Actions OIDC Outputs
# ------------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC Authentication"
  value       = module.iam.github_actions_role_arn
}
