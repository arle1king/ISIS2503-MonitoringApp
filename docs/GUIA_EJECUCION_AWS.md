# Guía de Ejecución de Experimentos en AWS

Instrucciones paso-a-paso para desplegar la infraestructura y ejecutar los tres experimentos ASR en una cuenta AWS.

## Tabla de Contenidos
1. [Prerequisitos](#prerequisitos)
2. [Configuración Inicial](#configuración-inicial)
3. [Despliegue de Infraestructura](#despliegue-de-infraestructura)
4. [Ejecución de Tests](#ejecución-de-tests)
5. [Monitoreo de Experimentos](#monitoreo-de-experimentos)
6. [Troubleshooting](#troubleshooting)
7. [Limpieza (Destroy)](#limpieza-destroy)

---

## Prerequisitos

### 1. Cuenta AWS
- Cuenta AWS activa con acceso a us-east-1 (región configurada en Terraform)
- **Nota:** Usa una cuenta de **desarrollo o staging**, NO producción

### 2. Permisos IAM Mínimos Requeridos
Necesitas una política IAM que incluya permisos en:
- **EC2**: `ec2:*` (instancias, security groups, volumes)
- **RDS**: `rds:*` (bases de datos, clusters, snapshots)
- **ALB/ELB**: `elasticloadbalancing:*` (load balancers, target groups)
- **Auto Scaling**: `autoscaling:*` (ASG, launch templates)
- **DynamoDB**: `dynamodb:*` (tablas, streams)
- **S3**: `s3:*` (buckets, Object Lock)
- **Lambda**: `lambda:*` (funciones, roles)
- **EventBridge**: `events:*` (rules, targets)
- **WAF**: `wafv2:*` (reglas, asociaciones)
- **KMS**: `kms:*` (claves, encriptación)
- **CloudWatch**: `cloudwatch:*` (métricas, logs, alarmas)
- **IAM**: `iam:CreateRole`, `iam:PutRolePolicy`, `iam:PassRole` (para roles de Terraform)
- **VPC**: `ec2:*` en VPC/subnets/routing

**Política JSON recomendada (para dev):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "rds:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "dynamodb:*",
        "s3:*",
        "lambda:*",
        "events:*",
        "wafv2:*",
        "kms:*",
        "cloudwatch:*",
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:PassRole",
        "iam:GetRole",
        "iam:DeleteRole",
        "iam:DeleteRolePolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. Herramientas Locales Instaladas

```bash
# 1. AWS CLI v2
aws --version
# Esperado: aws-cli/2.x.x

# 2. Terraform v1.0+
terraform --version
# Esperado: Terraform v1.x.x

# 3. Python 3.9+
python --version
# Esperado: Python 3.9.x o superior

# 4. Git (para clonar el repo)
git --version
```

---

## Configuración Inicial

### Paso 1: Clonar el Repositorio (si no lo has hecho)

```bash
git clone https://github.com/ISIS2503/ISIS2503-MonitoringApp.git
cd ISIS2503-MonitoringApp
```

### Paso 2: Configurar AWS CLI

```bash
# Configura credenciales AWS
aws configure

# Te pedirá:
# AWS Access Key ID: [tu_access_key_id]
# AWS Secret Access Key: [tu_secret_access_key]
# Default region name: us-east-1
# Default output format: json
```

**Verificación:**
```bash
aws sts get-caller-identity
# Debería mostrar tu cuenta AWS, usuario IAM, ARN
```

### Paso 3: Instalar Dependencias Python

```bash
# Crea virtualenv (recomendado)
python -m venv venv
source venv/Scripts/activate  # En Windows
# o: source venv/bin/activate (En Linux/Mac)

# Instala dependencias de la app
pip install -r requirements.txt

# Instala dependencias de tests
pip install -r requirements-test.txt

# Verifica pytest
pytest --version
# Esperado: pytest 7.x.x
```

### Paso 4: Revisar Configuración de Entorno

```bash
# En ISIS2503-MonitoringApp/terraform/environments/dev/

# Verifica terraform.tfvars (valores por defecto están bien para dev)
cat terraform/environments/dev/terraform.tfvars

# Salida esperada:
# asg_min_size             = 2
# asg_max_size             = 3
# asg_desired_capacity     = 2
# rds_instance_class       = "db.t3.micro"
# rds_allocated_storage    = 20
# enable_monitoring        = true
```

---

## Despliegue de Infraestructura

### Paso 1: Inicializar Terraform

```bash
cd ISIS2503-MonitoringApp/terraform/environments/dev

terraform init

# Esperado:
# Terraform has been successfully configured!
# You can now begin working with Terraform. Try running "terraform plan" to see
# any changes that would be made to your current infrastructure.
```

**Si falla con "no credentials":**
```bash
# Verifica que AWS CLI esté configurado
aws sts get-caller-identity

# Si devuelve error, vuelve a: aws configure
```

### Paso 2: Plan (Vista Previa)

```bash
terraform plan -out=tfplan

# Esperado:
# Plan: XX to add, 0 to change, 0 to destroy.
# 
# Saved the plan to: tfplan
```

**Revisar el plan:**
- VPC con 2 subnets (Multi-AZ)
- ALB con health check (2s)
- ASG con 2 instancias EC2 (t3.medium en dev)
- RDS Multi-AZ (db.t3.micro en dev)
- DynamoDB audit table + checksum table
- S3 bucket con Object Lock
- Lambda + EventBridge para integridad
- WAF + Security Groups para confidencialidad

### Paso 3: Aplicar (Crear Infraestructura)

```bash
terraform apply tfplan

# Esperado:
# Apply complete! Resources have been created.
# 
# Outputs:
# alb_dns_name = "dev-alb-XXXX.us-east-1.elb.amazonaws.com"
# rds_endpoint = "dev-db-instance.XXXX.us-east-1.rds.amazonaws.com"
# s3_bucket_name = "dev-monitoring-audit-XXXX"
```

**Tiempo estimado:** 10-15 minutos (RDS + ASG pueden tardar)

**Guardar outputs para próximos pasos:**
```bash
terraform output -json > outputs.json

# Guarda el DNS del ALB, endpoint RDS, etc.
cat outputs.json
```

### Paso 4: Verificar Despliegue

```bash
# Espera 2-3 minutos a que ALB + ASG estén listos

# Verifica ALB activo
curl -I http://$(terraform output -raw alb_dns_name)/health/

# Esperado: HTTP/1.1 200 OK

# Verifica instancias en ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-asg \
  --region us-east-1

# Esperado: "DesiredCapacity": 2, "Instances": [ { "InstanceId": "i-xxxxx", "HealthStatus": "Healthy" } ]

# Verifica RDS Multi-AZ
aws rds describe-db-instances \
  --db-instance-identifier dev-db-instance \
  --region us-east-1

# Esperado: "MultiAZ": true, "DBInstanceStatus": "available"
```

---

## Ejecución de Tests

### Contexto: Tests Unitarios vs Integración

- **Tests Unitarios** (no necesitan AWS):
  - `tests/integrity_tests/test_integrity.py` (con monkeypatch)
  - Ejecutar localmente: `pytest -m "not integration"`

- **Tests de Integración** (necesitan AWS):
  - `tests/availability_tests/test_availability.py`
  - `tests/confidentiality_tests/test_confidentiality.py`
  - Ejecutar en AWS: `pytest --run-aws`

### Paso 1: Ejecutar Tests Unitarios (Local, Sin AWS)

```bash
cd ISIS2503-MonitoringApp

# Verifica que pytest-django esté configurado
pytest --collect-only -m "not integration" | head -20

# Ejecuta tests unitarios
pytest -m "not integration" -v

# Esperado:
# tests/integrity_tests/test_integrity.py::test_checksum_generation PASSED
# tests/integrity_tests/test_integrity.py::test_audit_trail_immutability PASSED
# tests/integrity_tests/test_integrity.py::test_report_validation PASSED
# ... más tests ...
# ===== X passed in Y.XXs =====
```

### Paso 2: Ejecutar Tests de Integración (Contra AWS)

**Primero, configura variables de entorno para acceso a AWS:**

```bash
# Set AWS region
export AWS_REGION=us-east-1

# Opción A: Usar credenciales de AWS CLI (automático)
# O Opción B: Exportar explícitamente (si tienes múltiples profiles)
export AWS_PROFILE=default

# Verifica acceso a AWS
aws sts get-caller-identity
```

**Luego, ejecuta los tests de integración:**

```bash
# Ejecuta TODOS los tests de integración
pytest --run-aws -v

# O ejecuta solo los de Disponibilidad
pytest tests/availability_tests/ --run-aws -v

# O ejecuta solo los de Confidencialidad
pytest tests/confidentiality_tests/ --run-aws -v

# O ejecuta solo los de Integridad (integración)
pytest tests/integrity_tests/test_integrity.py --run-aws -v
```

**Esperado por Experimento:**

#### Experimento 1: Disponibilidad
```
tests/availability_tests/test_availability.py::test_alb_health_check_active PASSED
tests/availability_tests/test_availability.py::test_asg_minimum_size PASSED
tests/availability_tests/test_availability.py::test_rds_multi_az_enabled PASSED
tests/availability_tests/test_availability.py::test_failover_detection_time SKIPPED (requiere intervención manual)
...
===== X passed, Y skipped in Z.XXs =====
```

#### Experimento 2: Confidencialidad
```
tests/confidentiality_tests/test_confidentiality.py::test_waf_enabled PASSED
tests/confidentiality_tests/test_confidentiality.py::test_sql_injection_blocked PASSED
tests/confidentiality_tests/test_confidentiality.py::test_rate_limiting_enforced PASSED
tests/confidentiality_tests/test_confidentiality.py::test_security_group_restrictions PASSED
...
===== X passed in Y.XXs =====
```

#### Experimento 3: Integridad
```
tests/integrity_tests/test_integrity.py::test_checksum_generation PASSED
tests/integrity_tests/test_integrity.py::test_consume_integrity_validation PASSED
tests/integrity_tests/test_integrity.py::test_reject_modified_report PASSED
...
===== X passed in Y.XXs =====
```

### Paso 3: Generar Reporte de Tests

```bash
# Genera reporte en formato HTML
pytest --run-aws -v --html=report.html --self-contained-html

# Abre en navegador
# Windows: start report.html
# Mac: open report.html
# Linux: xdg-open report.html
```

---

## Monitoreo de Experimentos

### Dashboard CloudWatch Manual

```bash
# Ve a AWS Console
# CloudWatch > Dashboards > Crear nuevo dashboard

# Agrega métricas por experimento:

# === DISPONIBILIDAD ===
# - ALB > Target Group Health (HealthyHostCount, UnhealthyHostCount)
# - Auto Scaling > Group Metrics (GroupDesiredCapacity, GroupInServiceInstances)
# - RDS > Database Connections (DatabaseConnections)
# - RDS > Failover Activity (ReplicaLag - debe ser < 1 segundo)

# === CONFIDENCIALIDAD ===
# - WAF > Blocked Requests (BlockedRequests)
# - WAF > Allowed Requests (AllowedRequests)
# - VPC Flow Logs > Rejected Connections

# === INTEGRIDAD ===
# - DynamoDB > Consumed Write Capacity Units (audit table)
# - Lambda > Invocations (validation function)
# - Lambda > Errors (debe ser 0)
# - S3 > Object Count (audit bucket)
```

### Logs en CloudWatch

```bash
# Ver logs de aplicación
aws logs tail /aws/ec2/monitoring --follow --region us-east-1

# Ver logs de RDS
aws logs tail /aws/rds/instance/dev-db-instance --follow --region us-east-1

# Ver logs de Lambda
aws logs tail /aws/lambda/dev-integrity-validator --follow --region us-east-1
```

### Verificar Métricas por Experimento

```bash
# DISPONIBILIDAD: Health Check Status
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names dev-targets --region us-east-1 --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --region us-east-1

# Esperado: "HealthCheckState": "healthy" para ambas instancias

# CONFIDENCIALIDAD: WAF Blocked
aws wafv2 get-web-acl-for-resource \
  --resource-arn $(aws elbv2 describe-load-balancers --names dev-alb --region us-east-1 --query 'LoadBalancers[0].LoadBalancerArn' --output text) \
  --scope REGIONAL \
  --region us-east-1

# INTEGRIDAD: Audit Trail Count
aws dynamodb scan \
  --table-name dev-audit-trail \
  --region us-east-1

# Esperado: "Count": X > 0
```

---

## Troubleshooting

### Problema: `terraform init` falla con "no credentials found"

**Solución:**
```bash
# Verifica AWS CLI configurado
aws sts get-caller-identity

# Si falla, ejecuta:
aws configure

# Ingresa credenciales nuevamente
```

### Problema: `terraform apply` falla con "permission denied"

**Solución:**
```bash
# Verifica que tu usuario IAM tiene permisos suficientes
aws iam get-user

# Pide al administrador que agregue la política IAM (ver Prerequisitos)

# Verifica permisos específicos:
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:user/YOUR_USER \
  --action-names ec2:RunInstances rds:CreateDBInstance \
  --resource-arns "*"
```

### Problema: ALB no está healthy después de 15 minutos

**Solución:**
```bash
# 1. Verifica security groups
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --region us-east-1

# 2. SSH a instancia EC2 y verifica Django app
# (requiere EC2 key pair configurado)
ssh -i key.pem ec2-user@instance-public-ip
sudo systemctl status monitoring  # Ver estado de la app

# 3. Revisa logs de EC2
# EC2 > Instances > Selecciona instance > Connect > EC2 Instance Connect
sudo tail -f /var/log/cloud-init-output.log
```

### Problema: RDS no está "available" después de 10 minutos

**Solución:**
```bash
# Espera más tiempo (RDS Multi-AZ puede tardar 15-20 min)
aws rds describe-db-instances \
  --db-instance-identifier dev-db-instance \
  --region us-east-1 \
  --query 'DBInstances[0].DBInstanceStatus'

# Si queda en "creating", espera
# Si queda en "rebooting", puede haber un problema
# Si queda en "incompatible-parameters", verifica los valores de terraform.tfvars
```

### Problema: Tests se saltan todos con `--run-aws`

**Solución:**
```bash
# Verifica que pytest-django esté instalado
pip list | grep pytest-django

# Verifica que DJANGO_SETTINGS_MODULE esté en pytest.ini
cat pytest.ini | grep DJANGO_SETTINGS_MODULE

# Ejecuta con verbose para ver por qué se saltan
pytest --run-aws -v -s tests/availability_tests/test_availability.py::test_alb_health_check_active

# Si todavía se salta, verifica conftest.py
cat tests/conftest.py
```

### Problema: Test falla con "Connection refused" a ALB

**Solución:**
```bash
# 1. Verifica que ALB está en "active"
aws elbv2 describe-load-balancers \
  --names dev-alb \
  --region us-east-1

# 2. Verifica que DNS del ALB es alcanzable
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -v http://$ALB_DNS/health/

# 3. Si no responde, verifica targets
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names dev-targets --region us-east-1 --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --region us-east-1

# 4. Espera más (health check inicial puede tardar 2-3 minutos)
```

---

## Limpieza (Destroy)

### Paso 1: Destruir Infraestructura

```bash
cd ISIS2503-MonitoringApp/terraform/environments/dev

# Verifica lo que se va a destruir
terraform plan -destroy

# Destruye todo
terraform destroy -auto-approve

# Esperado:
# Destroy complete! Resources destroyed.
# State file backed up to terraform.tfstate.backup
```

**Tiempo estimado:** 5-10 minutos

### Paso 2: Verificar Limpieza (Opcional)

```bash
# Verifica que ALB esté destruido
aws elbv2 describe-load-balancers --region us-east-1

# Verifica que RDS esté destruido
aws rds describe-db-instances --region us-east-1

# Verifica que ASG esté destruido
aws autoscaling describe-auto-scaling-groups --region us-east-1
```

---

## Checklist de Ejecución Exitosa

- [ ] AWS CLI configurado (`aws sts get-caller-identity` funciona)
- [ ] Terraform init exitoso
- [ ] Terraform apply completo (10-15 minutos)
- [ ] ALB responde a `/health/` con HTTP 200
- [ ] RDS está en estado "available"
- [ ] ASG tiene 2 instancias "healthy"
- [ ] Tests unitarios pasan: `pytest -m "not integration" -v`
- [ ] Tests de disponibilidad pasan: `pytest tests/availability_tests/ --run-aws -v`
- [ ] Tests de confidencialidad pasan: `pytest tests/confidentiality_tests/ --run-aws -v`
- [ ] Tests de integridad pasan: `pytest tests/integrity_tests/ --run-aws -v`
- [ ] CloudWatch muestra métricas (HealthyHostCount > 0, Lambda invocations > 0)
- [ ] Terraform destroy exitoso (limpieza sin errores)

---

## Referencias

- [EXPERIMENTOS_ADAPTADOS.md](EXPERIMENTOS_ADAPTADOS.md) - Detalles de los 3 experimentos ASR
- [TESTS.md](../TESTS.md) - Ejecución local de tests sin AWS
- [TERRAFORM_GUIDE.md](../TERRAFORM_GUIDE.md) - Detalles de infraestructura
- [ARQUITECTURA_VISUAL.md](ARQUITECTURA_VISUAL.md) - Diagramas de arquitectura

