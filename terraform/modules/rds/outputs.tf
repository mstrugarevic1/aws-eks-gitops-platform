output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "address" {
  value = aws_db_instance.this.address
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed master password secret in Secrets Manager."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}
