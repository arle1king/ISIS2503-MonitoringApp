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
  type = string
}

variable "log_group_name" {
  type = string
}

variable "db_endpoint" {
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

variable "source_db_arn" {
  type        = string
  description = "ARN de la base de datos fuente para replicación"
}
