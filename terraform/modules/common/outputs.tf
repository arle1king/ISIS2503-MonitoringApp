output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID de la VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs de las subnets públicas"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "IDs de las subnets privadas"
}

output "base_security_group_id" {
  value       = aws_security_group.base.id
  description = "ID del security group base"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "ID del security group ALB"
}

output "database_security_group_id" {
  value       = aws_security_group.database.id
  description = "ID del security group de base de datos"
}

output "db_subnet_group_name" {
  value       = aws_db_subnet_group.main.name
  description = "Nombre del subnet group de RDS"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.main.name
  description = "Nombre del CloudWatch log group"
}
