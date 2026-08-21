output "gitea_irsa_role_arn" {
  description = "The ARN of the IAM role for Gitea application pods"
  value       = aws_iam_role.gitea.arn
}

output "gitea_irsa_role_name" {
  description = "The name of the IAM role for Gitea application pods"
  value       = aws_iam_role.gitea.name
}

output "alb_controller_irsa_role_arn" {
  description = "The ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "efs_csi_irsa_role_arn" {
  description = "The ARN of the IAM role for AWS EFS CSI Driver"
  value       = aws_iam_role.efs_csi.arn
}

output "github_actions_role_arn" {
  description = "The ARN of the IAM role for GitHub Actions OIDC Authentication"
  value       = aws_iam_role.github_actions_ecr.arn
}
