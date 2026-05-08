variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "Región de AWS"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Lista de zonas de disponibilidad"
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks permitidos para SSH"
  type        = list(string)
}

variable "log_retention_days" {
  description = "Días de retención para CloudWatch logs"
  type        = number
  default     = 7
}
