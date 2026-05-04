output "db_arn" {
  description = "ARN del secreto de la base de datos"
  value       = aws_db_instance.db-rds.master_user_secret[0].secret_arn
}