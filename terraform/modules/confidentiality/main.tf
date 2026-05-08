# Módulo de Confidencialidad
# ASR: Bloquear acceso no autorizado a datos de otra empresa (100%)
# Componentes:
# - VPC y subnet isolation por tenant/empresa
# - Security groups restrictivos
# - Encriptación en tránsito (TLS 1.2+) y en reposo
# - IAM roles con principio de mínimo privilegio
# - Data isolation en nivel de aplicación
# - AWS WAF para prevenir ataques de aplicación
# - VPC Flow Logs para auditoría

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# VPC Flow Logs para auditoría y compliance
resource "aws_flow_log" "main" {
  name                    = "${var.project_name}-flow-logs"
  iam_role_arn           = aws_iam_role.flow_logs.arn
  log_destination        = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type           = "ALL"
  vpc_id                 = var.vpc_id

  tags = {
    Name        = "${var.project_name}-flow-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.project_name}"
  retention_in_days = 90

  tags = {
    Name        = "${var.project_name}-vpc-flow-logs"
    Environment = var.environment
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flowlogs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-flowlogs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# AWS WAF para protección de aplicación
resource "aws_wafv2_ip_set" "blocked_ips" {
  name               = "${var.project_name}-blocked-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  address_set        = var.blocked_ip_list

  tags = {
    Name        = "${var.project_name}-blocked-ips"
    Environment = var.environment
  }
}

resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-waf"
  scope = "REGIONAL"

  # Rule 1: Bloquear IPs conocidas como maliciosas
  rule {
    name     = "BlockIPs"
    priority = 0

    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocked_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-BlockIPs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - SQL Injection Protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-SQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Rate limiting para prevenir fuerza bruta
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-waf"
    Environment = var.environment
  }
}

# Asociar WAF al Load Balancer
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# Security Group restrictivo para aplicación
resource "aws_security_group" "app_restricted" {
  name        = "${var.project_name}-app-restricted-sg"
  description = "Security group restrictivo para aplicación - Principio de mínimo privilegio"
  vpc_id      = var.vpc_id

  # Ingreso solo desde ALB
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Django from ALB only"
  }

  # SSH solo desde bastion o VPN
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
    description = "SSH from admin CIDR only"
  }

  # Egreso restrictivo
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound only"
  }

  # Egreso a base de datos
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.database_security_group_id]
    description     = "PostgreSQL to DB"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS queries"
  }

  tags = {
    Name        = "${var.project_name}-app-restricted-sg"
    Environment = var.environment
  }
}

# KMS Key para encriptación de datos
resource "aws_kms_key" "main" {
  description             = "KMS key para ${var.project_name} - Confidencialidad"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-kms-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.main.key_id
}

# KMS Key Policy
resource "aws_kms_key_policy" "main" {
  key_id = aws_kms_key.main.id

  policy = jsonencode({
    Id = "key-policy-1"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow services to use the key"
        Effect = "Allow"
        Principal = {
          Service = [
            "rds.amazonaws.com",
            "s3.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role para aplicación Django
resource "aws_iam_role" "django_confidential" {
  name = "${var.project_name}-django-confidential-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy con mínimos permisos
resource "aws_iam_role_policy" "django_confidential" {
  name = "${var.project_name}-django-confidential-policy"
  role = aws_iam_role.django_confidential.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:${var.log_group_name}:*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.main.arn
      },
      {
        Sid    = "SSMParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/confidential/*"
      }
    ]
  })
}

# RDS Database con encriptación
resource "aws_db_instance" "postgres_encrypted" {
  identifier     = "${var.project_name}-db-encrypted"
  engine         = "postgres"
  engine_version = var.postgres_version

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  storage_type         = "gp3"
  
  # Encriptación obligatoria
  storage_encrypted            = true
  kms_key_id                   = aws_kms_key.main.arn
  
  # SSL/TLS para conexiones
  publicly_accessible = false

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.database_security_group_id]

  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  multi_az = true

  # Enable encryption for backups
  copy_tags_to_snapshot       = true
  
  parameter_group_name = aws_db_parameter_group.postgres_secure.name

  skip_final_snapshot = var.environment == "dev" ? true : false
  
  monitoring_interval    = 60
  monitoring_role_arn    = aws_iam_role.rds_monitoring.arn
  enable_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection = var.environment == "prod" ? true : false

  tags = {
    Name        = "${var.project_name}-db-encrypted"
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy.rds_monitoring]
}

# DB Parameter Group con seguridad
resource "aws_db_parameter_group" "postgres_secure" {
  family = "postgres${var.postgres_version}"
  name   = "${var.project_name}-pg-secure"

  # Forzar SSL
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Logging de queries
  parameter {
    name  = "log_statement"
    value = "all"
  }

  tags = {
    Name        = "${var.project_name}-pg-secure"
    Environment = var.environment
  }
}

# IAM Role para monitoreo de RDS
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-confidential"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms para detección de acceso no autorizado
resource "aws_cloudwatch_log_group" "security_events" {
  name              = "/aws/${var.project_name}/security-events"
  retention_in_days = 90

  tags = {
    Name        = "${var.project_name}-security-events"
    Environment = var.environment
  }
}

# Metric Filter para detección de intentos de acceso
resource "aws_cloudwatch_log_metric_filter" "unauthorized_access" {
  name           = "${var.project_name}-unauthorized-access"
  log_group_name = var.log_group_name
  filter_pattern = "[... , status_code = 403, ...]"

  metric_transformation {
    name      = "UnauthorizedAccessAttempts"
    namespace = "${var.project_name}/Security"
    value     = "1"
  }
}

# Alarm para intentos de acceso no autorizado
resource "aws_cloudwatch_metric_alarm" "unauthorized_access_alarm" {
  alarm_name          = "${var.project_name}-unauthorized-access-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAccessAttempts"
  namespace           = "${var.project_name}/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_actions       = [var.sns_topic_arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name        = "${var.project_name}-unauthorized-access-alarm"
    Environment = var.environment
  }
}

# CloudWatch Dashboard para Confidencialidad
resource "aws_cloudwatch_dashboard" "confidentiality" {
  dashboard_name = "${var.project_name}-confidentiality"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/WAF", "BlockedRequests", { stat = "Sum" }],
            ["AWS/WAF", "AllowedRequests", { stat = "Sum" }],
            [var.project_name/Security", "UnauthorizedAccessAttempts", { stat = "Sum" }],
            ["AWS/RDS", "DatabaseConnections"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Confidencialidad - Security Metrics"
        }
      }
    ]
  })
}
