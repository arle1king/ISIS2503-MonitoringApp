output "waf_arn" {
  value       = aws_wafv2_web_acl.main.arn
  description = "ARN del WAF"
}

output "kms_key_id" {
  value       = aws_kms_key.main.id
  description = "ID de la KMS key"
}

output "app_security_group_id" {
  value       = aws_security_group.app_restricted.id
  description = "ID del security group restrictivo"
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres_encrypted.endpoint
  description = "Endpoint de RDS encriptado"
}
