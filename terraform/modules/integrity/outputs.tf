output "audit_trail_table_name" {
  value       = aws_dynamodb_table.audit_trail.name
  description = "Nombre de la tabla de auditoría"
}

output "report_checksums_table_name" {
  value       = aws_dynamodb_table.report_checksums.name
  description = "Nombre de la tabla de checksums"
}

output "lambda_validation_arn" {
  value       = aws_lambda_function.data_validation.arn
  description = "ARN de la función Lambda de validación"
}

output "integrity_alerts_topic_arn" {
  value       = aws_sns_topic.integrity_alerts.arn
  description = "ARN del SNS Topic de alertas"
}
