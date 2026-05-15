# README: Infraestructura Terraform para ASR

## Descripción General

Este proyecto implementa la infraestructura en AWS como código (Infrastructure as Code) usando Terraform, específicamente diseñada para garantizar tres Architectural Significant Requirements (ASR):

1. **Disponibilidad**: Recuperación ante fallos < 5 segundos
2. **Confidencialidad**: Bloquear acceso no autorizado a datos de otras empresas (100%)
3. **Integridad**: Detectar y rechazar datos modificados antes de generación de reportes (100%)

## Adaptación a tus diagramas

La infraestructura modular de este repositorio ya cubre el modelo que mostraste en tus diagramas:

- **Disponibilidad**: `module.availability` representa el balanceador de carga, el grupo de autoescalado y la base de datos para el servidor de usuarios.
- **Confidencialidad**: `module.confidentiality` y `module.proxysql` representan WAF, aislamiento por tenant, ProxySQL, seguridad de red y cifrado.
- **Integridad**: `module.integrity` representa hashes inmutables, DynamoDB de auditoría, Lambda de validación y EventBridge.

Las variables que más vas a tocar para tu entrega son:

- Disponibilidad: `asg_min_size`, `asg_max_size`, `asg_desired_capacity`, `instance_type`, `enable_https`, `certificate_arn`.
- Confidencialidad: `allowed_ssh_cidrs`, `admin_cidrs`, `blocked_ip_list`, `db_username`, `db_password`.
- Integridad: `db_endpoint`, `db_username`, `db_password`, `source_db_arn`.

Para la parte de aplicación, `monitoring/settings.py` ya expone `ENABLE_HASH_UPLOAD`, `S3_BUCKET_HASHES` y `DEFAULT_TENANT` por variables de entorno.

La especificación completa y adaptada a tu caso está en [docs/EXPERIMENTOS_ADAPTADOS.md](../docs/EXPERIMENTOS_ADAPTADOS.md).

## Estructura del Proyecto

```
terraform/
├── modules/
│   ├── common/                 # VPC, networking, security base
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── availability/           # Multi-AZ, ALB, ASG, RDS Multi-AZ
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── user_data.sh
│   ├── confidentiality/        # WAF, encryption, security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── integrity/              # DynamoDB, Lambda, EventBridge
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/                    # Configuración de desarrollo
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/                   # Configuración de producción
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
└── README.md

tests/
├── availability_tests/
│   ├── __init__.py
│   └── test_availability.py    # Tests para ASR Disponibilidad
├── confidentiality_tests/
│   ├── __init__.py
│   └── test_confidentiality.py # Tests para ASR Confidencialidad
└── integrity_tests/
    ├── __init__.py
    └── test_integrity.py        # Tests para ASR Integridad

docs/
├── ASR_Disponibilidad.md       # Documentación ASR 1
├── ASR_Confidencialidad.md     # Documentación ASR 2
└── ASR_Integridad.md           # Documentación ASR 3
```

## Módulos Terraform

### 1. Módulo Common

Proporciona infraestructura base compartida:

- **VPC Multi-AZ**: Con subnets públicas y privadas
- **Internet Gateway**: Para acceso a internet
- **NAT Gateways**: Para acceso saliente desde subnets privadas
- **Route Tables**: Públicas y privadas (una por AZ)
- **Security Groups**: Base, ALB, Database
- **RDS Subnet Group**: Para bases de datos
- **CloudWatch Log Group**: Para logs centralizados

#### Variables principales:
```hcl
vpc_cidr          = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
log_retention_days = 7
```

#### Outputs:
- vpc_id
- public_subnet_ids
- private_subnet_ids
- base_security_group_id
- alb_security_group_id
- database_security_group_id

### 2. Módulo Availability

Implementa recuperación ante fallos < 5 segundos:

- **Application Load Balancer**: Con health checks rápidos (5s)
- **Target Group**: Con routing y stickiness
- **Launch Template**: Para EC2 con user_data
- **Auto Scaling Group**: Min 2, Max 6, Desired 3
- **RDS Multi-AZ**: Con automatic failover
- **CloudWatch Alarms**: Para escalado automático
- **CloudWatch Dashboard**: Monitoreo de disponibilidad

#### Variables principales:
```hcl
instance_type        = "t3.medium"
min_size            = 2
max_size            = 6
desired_capacity    = 3
postgres_version    = "15.3"
enable_https        = true/false
```

#### Outputs:
- alb_dns_name
- alb_arn
- target_group_arn
- asg_name
- rds_endpoint
- rds_address

### 3. Módulo Confidentiality

Implementa protección contra acceso no autorizado (100%):

- **AWS WAF**: Rate limiting, SQL injection protection, IP blocking
- **KMS Keys**: Para encriptación en reposo
- **Security Groups**: Restrictivos (mínimo privilegio)
- **VPC Flow Logs**: Para auditoría de tráfico
- **RDS Encriptado**: Storage encryption + SSL requerido
- **IAM Roles**: Con mínimos permisos
- **CloudWatch Alarms**: Detectan intentos de acceso no autorizado

#### Variables principales:
```hcl
admin_cidrs        = ["10.0.0.0/16"]
blocked_ip_list    = []
sns_topic_arn      = "arn:aws:sns:..."
```

#### Outputs:
- waf_arn
- kms_key_id
- app_security_group_id
- rds_endpoint

### 4. Módulo Integrity

Implementa validación de datos antes de reportes (100%):

- **DynamoDB Audit Trail**: CDC con inmutabilidad
- **DynamoDB Checksums**: Para validación de reportes
- **Lambda Function**: Valida integridad cada 5 minutos
- **EventBridge Rules**: Orquestan validaciones
- **KMS Encryption**: Para tablas DynamoDB
- **CloudWatch Alarms**: Detectan modificaciones no autorizadas

#### Variables principales:
```hcl
db_endpoint      = "monitoring-app-db.c9akciq32.us-east-1.rds.amazonaws.com"
db_username      = "admin"
db_password      = "..."
source_db_arn    = "arn:aws:rds:..."
```

#### Outputs:
- audit_trail_table_name
- report_checksums_table_name
- lambda_validation_arn
- integrity_alerts_topic_arn

## Despliegue

### Prerequisitos

```bash
# Instalar Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# Configurar AWS CLI
aws configure
# Ingresar: AWS Access Key ID, AWS Secret Access Key, Region (us-east-1)

# Instalar PyTest (para tests)
pip install pytest boto3
```

### Despliegue en Development

```bash
cd terraform/environments/dev

# 1. Copiar variables (y actualizar con valores reales)
cp variables.tf terraform.tfvars

# 2. Inicializar Terraform
terraform init

# 3. Validar configuración
terraform fmt -check
terraform validate

# 4. Ver plan
terraform plan -out=tfplan

# 5. Aplicar cambios
terraform apply tfplan

# 6. Obtener outputs
terraform output
```

### Despliegue en Production

```bash
cd terraform/environments/prod

# Mismo proceso que dev, pero con valores de prod
# - Instancias más grandes
# - HTTPS habilitado con certificado válido
# - Log retention de 90 días
# - Deletion protection en RDS

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Tests

### Ejecutar todos los tests

```bash
# Tests de Disponibilidad
pytest tests/availability_tests/test_availability.py -v

# Tests de Confidencialidad
pytest tests/confidentiality_tests/test_confidentiality.py -v

# Tests de Integridad
pytest tests/integrity_tests/test_integrity.py -v

# Todos juntos
pytest tests/ -v
```

### Tests específicos

```bash
# Solo pruebas de configuración (sin integración)
pytest tests/availability_tests/test_availability.py::TestAvailability -v

# Solo tests que requieren acceso a ALB (integración)
pytest tests/availability_tests/test_availability.py::TestAvailabilityLoadScenarios -v

# Test específico
pytest tests/availability_tests/test_availability.py::TestAvailability::test_alb_health_check_configuration -v
```

## Monitoreo

Acceder a CloudWatch dashboards:

```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:
```

Dashboards disponibles:
- `monitoring-app-main`: Overview general
- `monitoring-app-availability`: Métricas de disponibilidad
- `monitoring-app-confidentiality`: Métricas de seguridad
- `monitoring-app-integrity`: Métricas de integridad

## Limpieza

Para eliminar toda la infraestructura:

```bash
cd terraform/environments/dev

# Ver qué se va a eliminar
terraform plan -destroy

# Destruir
terraform destroy
```

## Troubleshooting

### Error: "VpcLimitExceeded"
```
Error: Error creating VPC: VpcLimitExceeded: The maximum number of VPCs has been exceeded.

Solución: Eliminar VPCs no usadas o pedir aumento de límite a AWS
```

### Error: "RDS Instance not found"
```
Error: Error waiting for DB Instance to become available: AuthFailure

Solución: Verificar que las credenciales de AWS están correctas
```

### Health Checks fallando
```
Symptom: ALB marca todas las instancias como unhealthy

Solución:
1. Verificar que aplicación Django está corriendo
2. Verificar que endpoint /health/ responde 200
3. Revisar security groups permiten puerto 8000
4. Revisar logs en /var/log/gunicorn_error.log
```

## Costos Estimados

### Development (t3.micro/t3.small)
- EC2: ~$10/mes (2 instancias)
- RDS: ~$15/mes (t3.micro)
- ALB: ~$15/mes
- DynamoDB: ~$5/mes (on-demand)
- **Total: ~$45/mes**

### Production (t3.large/t3.medium)
- EC2: ~$60/mes (3-6 instancias)
- RDS: ~$40/mes (t3.medium multi-AZ)
- ALB: ~$15/mes
- DynamoDB: ~$20/mes (on-demand)
- WAF: ~$5/mes
- **Total: ~$140/mes**

## Documentación Completa

Para más detalles sobre cada ASR, ver:

1. [ASR Disponibilidad](./docs/ASR_Disponibilidad.md) - Recuperación < 5 segundos
2. [ASR Confidencialidad](./docs/ASR_Confidencialidad.md) - Bloquear acceso no autorizado
3. [ASR Integridad](./docs/ASR_Integridad.md) - Detectar datos modificados

## Soporte

Para problemas o preguntas:

1. Revisar logs: `terraform apply` output
2. Revisar AWS Console para estado de recursos
3. Ejecutar tests para diagnosticar problemas
4. Revisar CloudWatch Logs para errores de aplicación

## Licencia

Este proyecto es propietario de ISIS2503.

## Autores

- Created: 2026
- Project: ISIS2503 Monitoring App
