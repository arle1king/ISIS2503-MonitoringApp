# Módulo de Confidencialidad - ProxySQL
# ASR: Aislamiento Multi-tenant (Confidencialidad)
# Componentes:
# - ProxySQL como enrutador inteligente de queries por tenant
# - Esquemas separados en RDS para cada empresa
# - Security Groups restrictivos
# - Audit logging de accesos

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Security Group para ProxySQL
resource "aws_security_group" "proxysql" {
  name        = "${var.project_name}-proxysql-sg"
  description = "Security group para ProxySQL (enrutador multi-tenant)"
  vpc_id      = var.vpc_id

  # Ingreso desde App Servers (puerto 3306 - MySQL)
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
    description     = "MySQL queries desde App Servers"
  }

  # Ingreso SSH desde admin
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH desde admin"
  }

  # Egreso hacia RDS (puerto 5432 - PostgreSQL)
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.database_security_group_id]
    description     = "PostgreSQL queries hacia RDS"
  }

  # Egreso a internet (para updates y logs)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS para updates"
  }

  tags = {
    Name        = "${var.project_name}-proxysql-sg"
    Environment = var.environment
  }
}

# EC2 para ProxySQL
resource "aws_instance" "proxysql" {
  ami           = var.ami_id
  instance_type = "t3.small"
  subnet_id     = var.private_subnet_ids[0]

  vpc_security_group_ids = [aws_security_group.proxysql.id]

  # User data para instalar y configurar ProxySQL
  user_data = base64encode(templatefile("${path.module}/proxysql_setup.sh", {
    db_host               = var.db_endpoint
    db_port               = 5432
    db_username           = var.db_username
    db_password           = var.db_password
    environment           = var.environment
    project_name          = var.project_name
    log_group_name        = var.log_group_name
  }))

  iam_instance_profile = aws_iam_instance_profile.proxysql.name

  monitoring {
    enabled = true
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.project_name}-proxysql"
    Environment = var.environment
    Service     = "ProxySQL-MultiTenant-Router"
  }

  depends_on = [aws_iam_instance_profile.proxysql]
}

# IAM Role para ProxySQL
resource "aws_iam_role" "proxysql" {
  name = "${var.project_name}-proxysql-role"

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

  tags = {
    Name        = "${var.project_name}-proxysql-role"
    Environment = var.environment
  }
}

# IAM Policy para ProxySQL (logs y KMS)
resource "aws_iam_role_policy" "proxysql" {
  name = "${var.project_name}-proxysql-policy"
  role = aws_iam_role.proxysql.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/${var.project_name}/proxysql:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "proxysql" {
  name = "${var.project_name}-proxysql-profile"
  role = aws_iam_role.proxysql.name
}

# CloudWatch Log Group para ProxySQL
resource "aws_cloudwatch_log_group" "proxysql" {
  name              = "/aws/${var.project_name}/proxysql"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-proxysql-logs"
    Environment = var.environment
  }
}

# CloudWatch Alarm: ProxySQL access denied (intentos de acceso no autorizado)
resource "aws_cloudwatch_metric_alarm" "proxysql_access_denied" {
  alarm_name          = "${var.project_name}-proxysql-access-denied"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ProxySQLAccessDenied"
  namespace           = "CustomMetrics/${var.project_name}"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_actions       = [var.sns_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    Service     = "ProxySQL"
    Environment = var.environment
  }
}

# Output: ProxySQL endpoint
output "proxysql_endpoint" {
  value       = aws_instance.proxysql.private_ip
  description = "IP privada de ProxySQL para conexiones desde App Servers"
}

output "proxysql_security_group_id" {
  value       = aws_security_group.proxysql.id
  description = "Security Group ID de ProxySQL"
}
