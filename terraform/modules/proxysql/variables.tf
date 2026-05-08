variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
  description = "Security Group ID de Application Servers"
}

variable "database_security_group_id" {
  type = string
  description = "Security Group ID de Database"
}

variable "ami_id" {
  type = string
  description = "AMI ID para EC2 ProxySQL"
}

variable "allowed_ssh_cidrs" {
  type = list(string)
  description = "CIDR blocks permitidos para SSH"
}

variable "db_endpoint" {
  type = string
  description = "Endpoint de RDS PostgreSQL"
}

variable "db_username" {
  type = string
  description = "Usuario de RDS"
}

variable "db_password" {
  type = string
  sensitive   = true
  description = "Contraseña de RDS"
}

variable "kms_key_arn" {
  type = string
  description = "ARN de KMS key para encriptación"
}

variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Días de retención de logs"
}

variable "sns_topic_arn" {
  type = string
  description = "ARN de SNS topic para alertas"
}
