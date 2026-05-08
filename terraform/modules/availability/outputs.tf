output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "DNS del Load Balancer"
}

output "alb_arn" {
  value       = aws_lb.main.arn
  description = "ARN del Load Balancer"
}

output "target_group_arn" {
  value       = aws_lb_target_group.django.arn
  description = "ARN del Target Group"
}

output "asg_name" {
  value       = aws_autoscaling_group.django.name
  description = "Nombre del Auto Scaling Group"
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "Endpoint de RDS"
}

output "rds_address" {
  value       = aws_db_instance.postgres.address
  description = "Dirección de RDS"
}
