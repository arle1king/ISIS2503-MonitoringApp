terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }
}

# Módulo Common - Infraestructura base
module "common" {
  source = "../../modules/common"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_cidr            = var.vpc_cidr
  availability_zones  = data.aws_availability_zones.available.names
  allowed_ssh_cidrs   = var.allowed_ssh_cidrs
  log_retention_days  = var.log_retention_days
}

# Data source para availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Módulo Availability - Recuperación ante fallos < 5 segundos
module "availability" {
  source = "../../modules/availability"

  project_name              = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  vpc_id                    = module.common.vpc_id
  public_subnet_ids         = module.common.public_subnet_ids
  private_subnet_ids        = module.common.private_subnet_ids
  alb_security_group_id     = module.common.alb_security_group_id
  base_security_group_id    = module.common.base_security_group_id
  database_security_group_id = module.common.database_security_group_id
  db_subnet_group_name      = module.common.db_subnet_group_name
  log_group_name            = module.common.log_group_name

  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.instance_type
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity

  db_endpoint         = module.availability.rds_address
  db_username         = var.db_username
  db_password         = var.db_password
  db_name             = var.db_name
  db_instance_class   = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_iops             = var.db_iops
  postgres_version    = var.postgres_version

  enable_https   = var.enable_https
  certificate_arn = var.certificate_arn
}

# Data source para AMI Ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Módulo Confidentiality - Bloquear acceso no autorizado (100%)
module "confidentiality" {
  source = "../../modules/confidentiality"

  project_name              = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  aws_account_id            = data.aws_caller_identity.current.account_id
  vpc_id                    = module.common.vpc_id
  alb_arn                   = module.availability.alb_arn
  alb_security_group_id     = module.common.alb_security_group_id
  database_security_group_id = module.common.database_security_group_id
  db_subnet_group_name      = module.common.db_subnet_group_name
  log_group_name            = module.common.log_group_name

  sns_topic_arn = aws_sns_topic.security_alerts.arn
  blocked_ip_list = var.blocked_ip_list
  admin_cidrs   = var.admin_cidrs

  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  postgres_version     = var.postgres_version
}

# Data source para obtener información de la cuenta
data "aws_caller_identity" "current" {}

# Módulo Integrity - Detectar y rechazar datos modificados (100%)
module "integrity" {
  source = "../../modules/integrity"

  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
  log_group_name = module.common.log_group_name

  db_endpoint     = module.availability.rds_address
  db_username     = var.db_username
  db_password     = var.db_password
  source_db_arn   = module.availability.rds_address
}

# SNS Topic para alertas de seguridad
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project_name}-security-alerts"

  tags = {
    Name        = "${var.project_name}-security-alerts"
    Environment = var.environment
  }
}

# Suscripción SNS para email (reemplazar con email real)
resource "aws_sns_topic_subscription" "security_alerts_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# CloudWatch Dashboard Principal
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-main"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime"],
            ["AWS/ApplicationELB", "HealthyHostCount"],
            ["AWS/ApplicationELB", "UnHealthyHostCount"],
            ["AWS/EC2", "CPUUtilization"],
            ["AWS/WAF", "BlockedRequests"],
            ["AWS/RDS", "DatabaseAvailability"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Sistema General - KPIs Principales"
        }
      }
    ]
  })
}

# Outputs
output "alb_dns_name" {
  value       = module.availability.alb_dns_name
  description = "DNS del Load Balancer"
}

output "rds_endpoint" {
  value       = module.availability.rds_endpoint
  description = "Endpoint de la base de datos"
}

output "waf_arn" {
  value       = module.confidentiality.waf_arn
  description = "ARN del WAF"
}

output "kms_key_id" {
  value       = module.confidentiality.kms_key_id
  description = "ID de la KMS key para confidencialidad"
}

output "audit_trail_table" {
  value       = module.integrity.audit_trail_table_name
  description = "Tabla de auditoría"
}
