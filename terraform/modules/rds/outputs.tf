output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "db_instance_endpoint" {
  description = "The connection endpoint in address:port format"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_port" {
  description = "The database port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "The database name"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "The master username for the database"
  value       = aws_db_instance.main.username
}

output "db_password_secret_arn" {
  description = "The ARN of the secret in AWS Secrets Manager containing the database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_security_group_id" {
  description = "The security group ID of the RDS instance"
  value       = aws_security_group.rds.id
}
