# ==============================================================================
# Outputs for Amazon ECR Module
# ==============================================================================

output "repository_url" {
  description = "The URL of the Amazon ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_arn" {
  description = "The ARN of the Amazon ECR repository"
  value       = aws_ecr_repository.main.arn
}

output "repository_name" {
  description = "The name of the Amazon ECR repository"
  value       = aws_ecr_repository.main.name
}

output "registry_id" {
  description = "The AWS Registry ID (Account ID) owning the repository"
  value       = aws_ecr_repository.main.registry_id
}
