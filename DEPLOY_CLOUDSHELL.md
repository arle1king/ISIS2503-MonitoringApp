# Despliegue en AWS CloudShell

## Pasos para comenzar en AWS CloudShell

### 1. Abrir CloudShell
```bash
# Desde AWS Console: CloudShell (esquina superior derecha)
# O accede directamente a: https://console.aws.amazon.com/cloudshell
```

### 2. Clonar el repositorio
```bash
cd ~
git clone https://github.com/ISIS2503/ISIS2503-MonitoringApp.git
cd ISIS2503-MonitoringApp
```

### 3. Configurar variables de entorno (importante para S3/DynamoDB)
```bash
export AWS_REGION=us-east-1
export DJANGO_SETTINGS_MODULE=monitoring.settings
export ENABLE_HASH_UPLOAD=True
export S3_BUCKET_HASHES=hashes-inmutables
export DEFAULT_TENANT=empresa_a
export RDS_HOST=monitoring-app.c9akciq32.us-east-1.rds.amazonaws.com
export RDS_USER=postgres
export RDS_PASSWORD=your_password_here
export RDS_DB=monitoring_db
```

### 4. Crear entorno virtual e instalar dependencias
```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install boto3 PyJWT
```

### 5. Crear migraciones Django
```bash
python manage.py makemigrations measurements
python manage.py makemigrations variables
python manage.py migrate
```

### 6. Crear buckets S3 (si no existen)
```bash
# Crear bucket para hashes inmutables
aws s3 mb s3://hashes-inmutables --region us-east-1

# (Opcional) Habilitar Object Lock si quieres inmutabilidad fuerte
# aws s3api put-object-lock-configuration \
#   --bucket hashes-inmutables \
#   --object-lock-configuration 'ObjectLockEnabled=Enabled,Rule={DefaultRetention={Mode=GOVERNANCE,Days=365}}'
```

### 7. Inicializar schemas en RDS
```bash
# Conectar a RDS e ejecutar SCHEMA.sql
psql -h $RDS_HOST -U $RDS_USER -d $RDS_DB -f variables/SCHEMA.sql

# O manualmente:
psql -h monitoring-app.c9akciq32.us-east-1.rds.amazonaws.com -U postgres -d monitoring_db

# Dentro de psql:
\i variables/SCHEMA.sql
\q
```

### 8. Insertar datos de ejemplo (tenants y usuarios)
```bash
python manage.py shell
```

Dentro del shell:
```python
from variables.models import Tenant, Usuario, Proyecto

# Crear tenants
t_a = Tenant.objects.create(key='empresa_a', display_name='Empresa A')
t_b = Tenant.objects.create(key='empresa_b', display_name='Empresa B')

# Crear proyectos
p1 = Proyecto.objects.create(tenant=t_a, name='Proyecto AWS', description='Infraestructura cloud')
p2 = Proyecto.objects.create(tenant=t_b, name='Proyecto GCP', description='Google Cloud')

# Crear usuarios
u1 = Usuario.objects.create(tenant=t_a, username='user_a', email='user_a@empresa_a.com', role='admin')
u2 = Usuario.objects.create(tenant=t_b, username='user_b', email='user_b@empresa_b.com', role='user')

print("✓ Datos iniciales creados")
exit()
```

### 9. Probar endpoint `/health`
```bash
curl http://localhost:8000/health
curl http://localhost:8000/health?db=1
```

### 10. Ejecutar management command para validación y subida de checksums
```bash
python manage.py validate_and_publish_checksums --tenant empresa_a --year 2026 --month 5
```

### 11. Ver logs y resultados en CloudWatch
```bash
# Ver logs de la aplicación
aws logs tail /aws/lambda/monitoring-app --follow

# O en CloudWatch Dashboards:
# https://console.aws.amazon.com/cloudwatch/home#dashboards:
```

---

## Configuración en Producción (EC2 + RDS + ALB)

### 1. Desplegar aplicación en EC2
```bash
# En la instancia EC2 (SSH)
ssh -i your_key.pem ec2-user@your-ec2-ip

# Clonar, instalar, migrar (como arriba)
git clone https://github.com/ISIS2503/ISIS2503-MonitoringApp.git
cd ISIS2503-MonitoringApp
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install boto3 PyJWT

# Hacer que la aplicación sea accesible en puerto 8000
python manage.py runserver 0.0.0.0:8000
```

### 2. Configurar ALB Health Check
En **AWS Console → EC2 → Target Groups**:
- **Health Check Path**: `/health`
- **Health Check Interval**: 2 segundos (recomendado para failover ≤ 5s)
- **Unhealthy Threshold**: 2 (intentos)
- **Expected HTTP Code**: 200

### 3. Verificar ProxySQL (confidencialidad)
```bash
# Conectar a ProxySQL (si está deployado)
mysql -h proxysql-ip -u admin_user -p

# Dentro de ProxySQL:
SELECT * FROM mysql_query_rules;
SELECT * FROM mysql_users;
```

### 4. Ejecutar pruebas
```bash
# En CloudShell o EC2:
pip install pytest pytest-django
pytest tests/integrity_tests/test_consume_integrity.py -v
pytest tests/integrity_tests/test_integrity.py -v
```

---

## Troubleshooting

### Error: "No module named 'boto3'"
```bash
pip install boto3
```

### Error: "RDS connection refused"
- Verificar RDS endpoint y security group
- Comprobar credenciales en variables de entorno
```bash
psql -h $RDS_HOST -U $RDS_USER -d $RDS_DB -c "SELECT 1"
```

### Error: "S3 bucket not found"
```bash
aws s3 ls  # ver buckets disponibles
aws s3 mb s3://hashes-inmutables --region us-east-1
```

### Error: "logs_auditoria table not found"
```bash
# Ejecutar migraciones:
python manage.py migrate measurements
python manage.py migrate variables
```

---

## Monitoreo continuo

### Ejecutar validaciones periódicas (Cron o EventBridge)
```bash
# Cron local (cada hora):
0 * * * * cd /path/to/app && python manage.py validate_and_publish_checksums --tenant empresa_a --year 2026 --month 5

# Desde AWS Console → EventBridge:
# - Crear regla con cron: cron(0 * * * ? *)
# - Target: Lambda que ejecuta el management command
```

### Ver dashboards CloudWatch
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:
```

---

## Resumen de lo implementado

✅ **Disponibilidad (ASR 1):**
- Endpoint `/health` para ALB health checks
- RDS Multi-AZ (failover automático)

✅ **Confidencialidad (ASR 2):**
- `TenantMiddleware` extrae tenant desde JWT/header
- Modelos `Tenant`, `Usuario`, `Proyecto` con aislamiento
- ProxySQL enrutador por tenant (ver terraform/modules/proxysql)

✅ **Integridad (ASR 3):**
- `ConsumoCloud` con SHA-256 hash de registros
- `LogsAuditoria` registra validaciones
- Management command sube checksums a S3
- Optional DynamoDB para inmutabilidad

✅ **Documentación:**
- `variables/ESQUEMA_BASE_DATOS.md` — patrón multi-tenant
- `variables/SCHEMA.sql` — SQL de inicialización
- `docs/INTEGRITY_PROCEDURE.md` — procedimiento
- Tests en `tests/integrity_tests/`

Próximos pasos:
1. Ejecutar los comandos arriba en CloudShell
2. Verificar que migraciones y datos se crean
3. Probar endpoints y management command
4. Configurar terraform si aún no está deployado
