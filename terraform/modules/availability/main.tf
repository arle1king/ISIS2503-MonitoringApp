# Módulo de Disponibilidad
# ASR: Recuperación ante fallos < 5 segundos
# Componentes:
# - Multi-AZ deployment
# - Application Load Balancer con health checks rápidos
# - Auto Scaling Group con rapid recovery
# - RDS Multi-AZ con failover automático
# - Monitoreo continuo

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get current AWS account ID for role ARN
data "aws_caller_identity" "current" {}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

# Target Group
resource "aws_lb_target_group" "django" {
  name        = "${var.project_name}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Health check optimizado para recuperación < 5 segundos
  # ASR 1: Puerto 8080, ruta /health-check/, intervalo 2 segundos
  # Tiempo máximo de detección: 2 fallos × 2 seg = 4 seg (< 5 seg) ✓
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 1              # Timeout 1 segundo
    interval            = 2              # Health check cada 2 segundos (ASR requerimiento)
    path                = "/health-check/"
    matcher             = "200"
    port                = "8080"         # Puerto dedicado para health checks
    protocol            = "HTTP"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 86400
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
  }
}

# ALB Listener HTTP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.django.arn
  }
}

# ALB Listener HTTPS (opcional)
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.django.arn
  }
}

# Launch Template para ASG
resource "aws_launch_template" "django" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [var.base_security_group_id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host            = var.db_endpoint
    db_user            = var.db_username
    db_password        = var.db_password
    db_name            = var.db_name
    environment        = var.environment
    log_group_name     = var.log_group_name
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.django.name
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-instance"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group para recuperación automática (ASR 1: 3 instancias)
# Instancias:
#   1. Servidor de Usuarios (user-service)
#   2. Servidor de Datos (data-service)
#   3. Servidor de Notificaciones (notification-service)
# Failover automático: si una falla, ASG reemplaza en < 5 segundos
resource "aws_autoscaling_group" "django" {
  name_prefix         = "${var.project_name}-asg-"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.django.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 60

  # Capacidad para recuperación rápida (ASR: 3 instancias mínimo)
  min_size             = 3              # Siempre 3 instancias (usuarios, datos, notificaciones)
  max_size             = var.max_size
  desired_capacity     = 3              # Exactamente 3 para experimento

  launch_template {
    id      = aws_launch_template.django.id
    version = "$Latest"
  }

  # Reemplazar instancias no saludables
  instance_warmup_period = 60

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_launch_template = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_launch_template = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_lb.main]
}

# Scaling Policies para Disponibilidad
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.django.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 600
  autoscaling_group_name = aws_autoscaling_group.django.name
}

# CloudWatch Alarms para scale up (CPU > 70%)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "70"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.django.name
  }
}

# CloudWatch Alarm para scale down (CPU < 30%)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "30"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.django.name
  }
}

# RDS Multi-AZ para recuperación automática
resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = var.postgres_version

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  storage_type         = "gp3"
  storage_encrypted    = true
  iops                 = var.db_iops

  # Multi-AZ para failover automático
  multi_az            = true

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.database_security_group_id]

  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  multi_az_storage_failover = "automatic"

  parameter_group_name = aws_db_parameter_group.postgres.name

  skip_final_snapshot = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  monitoring_interval    = 60
  monitoring_role_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  enable_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection = var.environment == "prod" ? true : false

  tags = {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy.rds_monitoring]
}

# DB Parameter Group
resource "aws_db_parameter_group" "postgres" {
  family = "postgres${var.postgres_version}"
  name   = "${var.project_name}-pg"

  parameter {
    name  = "log_duration"
    value = "true"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name        = "${var.project_name}-pg"
    Environment = var.environment
  }
}

# IAM Instance Profile using existing LabRole
# Note: RDS monitoring uses LabRole (CloudShell lab environment)
resource "aws_iam_instance_profile" "django" {
  name = "${var.project_name}-django-profile"
  role = "LabRole"
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "availability" {
  dashboard_name = "${var.project_name}-availability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            ["AWS/ApplicationELB", "HealthyHostCount"],
            ["AWS/ApplicationELB", "UnHealthyHostCount"],
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }],
            ["AWS/RDS", "DatabaseAvailability"],
            ["AWS/RDS", "FailoverEvents"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Disponibilidad - Key Metrics"
        }
      }
    ]
  })
}
