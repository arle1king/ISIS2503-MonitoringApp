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

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "base_security_group_id" {
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

variable "ami_id" {
  type        = string
  description = "AMI ID para las instancias EC2"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Tipo de instancia EC2"
}

variable "min_size" {
  type        = number
  default     = 2
  description = "Mínimo de instancias"
}

variable "max_size" {
  type        = number
  default     = 6
  description = "Máximo de instancias"
}

variable "desired_capacity" {
  type        = number
  default     = 3
  description = "Capacidad deseada"
}

variable "db_endpoint" {
  type        = string
  description = "Endpoint de la base de datos"
}

variable "db_username" {
  type        = string
  sensitive   = true
  description = "Usuario de la base de datos"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Contraseña de la base de datos"
}

variable "db_name" {
  type        = string
  description = "Nombre de la base de datos"
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

variable "db_iops" {
  type        = number
  default     = 3000
  description = "IOPS de RDS"
}

variable "postgres_version" {
  type        = string
  default     = "15.3"
  description = "Versión de PostgreSQL"
}

variable "enable_https" {
  type        = bool
  default     = false
  description = "Habilitar HTTPS"
}

variable "certificate_arn" {
  type        = string
  default     = ""
  description = "ARN del certificado ACM"
}
