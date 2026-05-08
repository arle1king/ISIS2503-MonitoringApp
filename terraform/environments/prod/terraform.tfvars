aws_region = "us-east-1"
environment = "prod"
project_name = "monitoring-app"

vpc_cidr = "10.0.0.0/16"
allowed_ssh_cidrs = ["10.0.0.0/16"]  # Solo desde VPN/Bastion
admin_cidrs = ["10.0.0.0/16"]
log_retention_days = 90

instance_type = "t3.large"
asg_min_size = 2
asg_max_size = 6
asg_desired_capacity = 3

db_username = "adminuser"
db_password = "PROD_PASSWORD_REQUIRED"  # Cambiar en deployment
db_name = "monitoring_db"
db_instance_class = "db.t3.medium"
db_allocated_storage = 100
db_iops = 3000
postgres_version = "15.3"

enable_https = true
certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERTIFICATE_ID"  # Cambiar

blocked_ip_list = [
  # Agregar IPs maliciosas conocidas aquí
  # "203.0.113.1/32"
]

admin_email = "security-team@example.com"
