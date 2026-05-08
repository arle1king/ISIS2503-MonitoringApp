variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type        = string
  description = "AWS Account ID"
}

variable "vpc_id" {
  type = string
}

variable "alb_arn" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "database_security_group_id" {
  type = string
}

variable "db_subnet_group_name" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS Topic para alertas de seguridad"
}

variable "blocked_ip_list" {
  type        = list(string)
  default     = []
  description = "Lista de IPs a bloquear"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "CIDR blocks para acceso de administración"
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type        = string
  default     = "db.t3.medium"
  description = "Clase de instancia RDS"
}

variable "db_allocated_storage" {
  type        = number
  default     = 100
  description = "Almacenamiento RDS en GB"
}

variable "postgres_version" {
  type        = string
  default     = "15.3"
  description = "Versión de PostgreSQL"
}
