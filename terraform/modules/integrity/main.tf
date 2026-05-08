# Módulo de Integridad - ASR 3
# ASR: Detectar y rechazar datos modificados antes de generación de reporte (100%)
# Componentes:
# - S3 con Object Lock (WORM) para almacenamiento inmutable de hashes
# - Lambda para SHA-256 hashing y validación
# - DynamoDB para audit trail
# - EventBridge para orquestación

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data source para account ID y region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 Bucket con Object Lock para almacenamiento inmutable de hashes
resource "aws_s3_bucket" "audit_hashes_immutable" {
  bucket = "${var.project_name}-audit-hashes-immutable-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project_name}-audit-hashes-immutable"
    Environment = var.environment
    Service     = "ASR3-IntegrityVerification"
  }
}

# Habilitar Object Lock (Write-Once-Read-Many)
resource "aws_s3_bucket_object_lock_configuration" "audit_hashes" {
  bucket = aws_s3_bucket.audit_hashes_immutable.id

  rule {
    default_retention {
      mode = "COMPLIANCE"  # No se puede borrar ni modificar
      days = 365           # Retener por 1 año mínimo
    }
  }
}

# Versionado para PITR
resource "aws_s3_bucket_versioning" "audit_hashes" {
  bucket = aws_s3_bucket.audit_hashes_immutable.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación con KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "audit_hashes" {
  bucket = aws_s3_bucket.audit_hashes_immutable.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.integrity.arn
    }
    bucket_key_enabled = true
  }

  depends_on = [aws_kms_key.integrity]
}

# Bloquear acceso público
resource "aws_s3_bucket_public_access_block" "audit_hashes" {
  bucket = aws_s3_bucket.audit_hashes_immutable.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Logging de accesos a S3
resource "aws_s3_bucket_logging" "audit_hashes" {
  bucket = aws_s3_bucket.audit_hashes_immutable.id

  target_bucket = aws_s3_bucket.audit_hashes_logs.id
  target_prefix = "s3-access-logs/"
}

# Bucket para logs de S3
resource "aws_s3_bucket" "audit_hashes_logs" {
  bucket = "${var.project_name}-audit-hashes-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project_name}-audit-hashes-logs"
    Environment = var.environment
  }
}

# Permitir S3 escribir logs
resource "aws_s3_bucket_acl" "audit_hashes_logs" {
  bucket = aws_s3_bucket.audit_hashes_logs.id
  acl    = "log-delivery-write"
}

# DynamoDB para almacenar checksums y auditoría
resource "aws_dynamodb_table" "audit_trail" {
  name           = "${var.project_name}-audit-trail"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "EntityId"
  range_key      = "Timestamp"

  attribute {
    name = "EntityId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "ExpirationTime"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.integrity.arn
  }

  tags = {
    Name        = "${var.project_name}-audit-trail"
    Environment = var.environment
  }

  depends_on = [aws_kms_key.integrity]
}

# DynamoDB para checksums de reportes
resource "aws_dynamodb_table" "report_checksums" {
  name           = "${var.project_name}-report-checksums"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ReportId"
  range_key      = "GeneratedAt"

  attribute {
    name = "ReportId"
    type = "S"
  }

  attribute {
    name = "GeneratedAt"
    type = "N"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.integrity.arn
  }

  tags = {
    Name        = "${var.project_name}-report-checksums"
    Environment = var.environment
  }

  depends_on = [aws_kms_key.integrity]
}

# KMS Key para integridad
resource "aws_kms_key" "integrity" {
  description             = "KMS key para ${var.project_name} - Integridad"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-integrity-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "integrity" {
  name          = "alias/${var.project_name}-integrity"
  target_key_id = aws_kms_key.integrity.key_id
}

# Lambda Function para validación de datos
resource "aws_iam_role" "lambda_validation" {
  name = "${var.project_name}-lambda-validation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_validation" {
  name = "${var.project_name}-lambda-validation-policy"
  role = aws_iam_role.lambda_validation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.audit_trail.arn,
          aws_dynamodb_table.report_checksums.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.integrity.arn
      },
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function para detectar cambios no autorizados
resource "aws_lambda_function" "data_validation" {
  filename      = "lambda_validation.zip"
  function_name = "${var.project_name}-data-validation"
  role          = aws_iam_role.lambda_validation.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      AUDIT_TABLE_NAME     = aws_dynamodb_table.audit_trail.name
      CHECKSUM_TABLE_NAME  = aws_dynamodb_table.report_checksums.name
      DB_HOST              = var.db_endpoint
      DB_USER              = var.db_username
      DB_PASSWORD          = var.db_password
      KMS_KEY_ID           = aws_kms_key.integrity.id
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_validation,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-data-validation"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-lambda-logs"
    Environment = var.environment
  }
}

# EventBridge Rule para ejecutar validación periódicamente
resource "aws_cloudwatch_event_rule" "integrity_check" {
  name                = "${var.project_name}-integrity-check"
  description         = "Ejecutar validación de integridad cada 5 minutos"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name        = "${var.project_name}-integrity-check-rule"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.integrity_check.name
  target_id = "LambdaValidationTarget"
  arn       = aws_lambda_function.data_validation.arn

  input = jsonencode({
    action = "validate_data"
    type   = "periodic"
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_validation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.integrity_check.arn
}

# SNS Topic para alertas de integridad
resource "aws_sns_topic" "integrity_alerts" {
  name              = "${var.project_name}-integrity-alerts"
  kms_master_key_id = aws_kms_key.integrity.id

  tags = {
    Name        = "${var.project_name}-integrity-alerts"
    Environment = var.environment
  }
}

# CloudWatch Alarms para integridad
resource "aws_cloudwatch_log_metric_filter" "data_modification" {
  name           = "${var.project_name}-data-modification"
  log_group_name = var.log_group_name
  filter_pattern = "[... , operation = UPDATE OR operation = DELETE, ...]"

  metric_transformation {
    name      = "UnauthorizedDataModification"
    namespace = "${var.project_name}/Integrity"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "data_integrity_alarm" {
  alarm_name          = "${var.project_name}-data-integrity-violation"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedDataModification"
  namespace           = "${var.project_name}/Integrity"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_actions       = [aws_sns_topic.integrity_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name        = "${var.project_name}-data-integrity-alarm"
    Environment = var.environment
  }
}

# RDS Backup con validación
resource "aws_db_instance_automated_backups_replication" "postgres_backup" {
  source_db_instance_arn = var.source_db_arn
  retention_period       = 30

  kms_key_id = aws_kms_key.integrity.arn

  depends_on = [aws_kms_key.integrity]
}

# CloudWatch Dashboard para Integridad
resource "aws_cloudwatch_dashboard" "integrity" {
  dashboard_name = "${var.project_name}-integrity"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["${var.project_name}/Integrity", "UnauthorizedDataModification", { stat = "Sum" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", { stat = "Sum" }],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Integridad - Data Validation Metrics"
        }
      }
    ]
  })
}

# EventBridge Rule para validar reportes antes de generación
resource "aws_cloudwatch_event_rule" "pre_report_validation" {
  name                = "${var.project_name}-pre-report-validation"
  description         = "Validar integridad antes de generar reportes"
  schedule_expression = "cron(0 1 * * MON-FRI *)"

  tags = {
    Name        = "${var.project_name}-pre-report-validation"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "pre_report_lambda" {
  rule      = aws_cloudwatch_event_rule.pre_report_validation.name
  target_id = "PreReportValidation"
  arn       = aws_lambda_function.data_validation.arn

  input = jsonencode({
    action = "validate_before_report"
    type   = "pre_report"
  })
}
