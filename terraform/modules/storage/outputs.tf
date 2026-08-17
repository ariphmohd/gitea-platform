output "efs_file_system_id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_access_point_id" {
  description = "The ID of the EFS access point"
  value       = aws_efs_access_point.gitea.id
}

output "efs_dns_name" {
  description = "The DNS name of the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "efs_security_group_id" {
  description = "The security group ID of the EFS file system"
  value       = aws_security_group.efs.id
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for Gitea storage"
  value       = aws_s3_bucket.gitea_storage.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket for Gitea storage"
  value       = aws_s3_bucket.gitea_storage.arn
}

output "s3_bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.gitea_storage.bucket_domain_name
}
