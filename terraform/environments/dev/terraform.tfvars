aws_region = "us-east-1"
environment = "dev"
project_name = "monitoring-app"

vpc_cidr = "10.0.0.0/16"
allowed_ssh_cidrs = ["0.0.0.0/0"]  # Cambiar en producción
admin_cidrs = ["0.0.0.0/0"]
log_retention_days = 7

instance_type = "t3.medium"
asg_min_size = 1
asg_max_size = 2
asg_desired_capacity = 1

db_username = "adminuser"
db_password = "ChangeMe123!"  # Cambiar a contraseña segura
db_name = "monitoring_db"
db_instance_class = "db.t3.micro"
db_allocated_storage = 20
db_iops = 3000
postgres_version = "15.3"

enable_https = false
certificate_arn = ""

blocked_ip_list = []
admin_email = "admin@example.com"
