# Guía: Terraform + Django en AWS CloudShell

## Orden de ejecución

```
1. Verificar si hay Terraform deployado (opcional)
2. Ejecutar Terraform para crear infraestructura
3. Obtener outputs (RDS endpoint, etc.)
4. Configurar Django y ejecutar migraciones
5. Probar endpoints
```

---

## Paso 1: Verificar Terraform (opcional)

En CloudShell:

```bash
# Ver si ya hay stacks de Terraform
cd ISIS2503-MonitoringApp

# Verificar archivos terraform
ls -la terraform/
ls -la terraform/environments/

# Ver state de terraform (si existe)
terraform -v
```

---

## Paso 2: Ejecutar Terraform en CloudShell

### 2.1 Instala Terraform (si no está)

```bash
# En CloudShell (tiene preinstalado, pero verifica)
terraform --version

# Si no está:
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform
```

### 2.2 Configura AWS credentials (CloudShell ya tiene permisos)

```bash
# CloudShell ya tiene credenciales de tu cuenta AWS, solo verifica:
aws sts get-caller-identity

# Output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/..."
# }
```

### 2.3 Ejecuta Terraform

```bash
cd terraform

# Selecciona ambiente (dev o prod)
cd environments/dev
# o
cd environments/prod

# Inicializa Terraform
terraform init

# Ver plan de cambios (no hace cambios, solo muestra)
terraform plan

# Crear infraestructura (ATENCION: esto crea recursos con costo)
terraform apply

# Cuando pregunte "Enter a value" → responde: yes
```

### 2.4 Obtén outputs de Terraform

```bash
# Ver todos los outputs
terraform output

# Ejemplo de output:
# alb_dns_name = "monitoring-alb-123456789.us-east-1.elb.amazonaws.com"
# rds_endpoint = "monitoring-app.c9akciq32.us-east-1.rds.amazonaws.com"
# rds_address = "monitoring-app.c9akciq32.us-east-1.rds.amazonaws.com"

# Guarda estos valores
export RDS_HOST=$(terraform output -raw rds_endpoint)
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export ALB_DNS=$(terraform output -raw alb_dns_name)

echo "RDS: $RDS_HOST"
echo "ALB: $ALB_DNS"
```

---

## Paso 3: Configura Django después de Terraform

```bash
# Vuelve a la raíz del proyecto
cd ~/ISIS2503-MonitoringApp

# Configura variables de entorno con los outputs de Terraform
export RDS_HOST=$(cd terraform/environments/dev && terraform output -raw rds_endpoint)
export RDS_USER=postgres
export RDS_PASSWORD=$(cd terraform/environments/dev && terraform output -raw db_password 2>/dev/null || echo "tu_password")
export RDS_DB=monitoring_db
export RDS_PORT=5432
export DJANGO_SETTINGS_MODULE=monitoring.settings
export ENABLE_HASH_UPLOAD=True
export S3_BUCKET_HASHES=hashes-inmutables
export DEFAULT_TENANT=empresa_a

# Verifica conectividad a RDS
psql -h $RDS_HOST -U $RDS_USER -d $RDS_DB -c "SELECT 1;"

# Si conecta, ejecuta migraciones
python manage.py migrate
```

---

## Paso 4: Si el RDS no existe aún (usar SQLite para testing local)

Si Terraform falla o RDS no está disponible, puedes testear localmente con SQLite:

### Opción A: SQLite (testing local rápido)

```bash
# Edita settings.py y reemplaza DATABASES a:
cat > settings_sqlite.py << 'EOF'
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),
    }
}
EOF

# O edita directamente en monitoring/settings.py:
# Busca la sección DATABASES y reemplaza con:
# DATABASES = {
#     'default': {
#         'ENGINE': 'django.db.backends.sqlite3',
#         'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),
#     }
# }

# Luego:
export DJANGO_SETTINGS_MODULE=monitoring.settings
python manage.py migrate

# Prueba el servidor
python manage.py runserver 0.0.0.0:8000

# En otra terminal de CloudShell, prueba:
curl http://localhost:8000/health
```

### Opción B: PostgreSQL Docker (si prefieres local con PostgreSQL)

```bash
# Inicia un PostgreSQL en Docker (si CloudShell lo soporta)
docker run -d --name postgres -e POSTGRES_PASSWORD=password -p 5432:5432 postgres:15

# Crea la base de datos
docker exec postgres psql -U postgres -c "CREATE DATABASE monitoring_db;"

# Configura variables
export RDS_HOST=localhost
export RDS_USER=postgres
export RDS_PASSWORD=password
export RDS_DB=monitoring_db

# Ejecuta migraciones
python manage.py migrate
```

---

## Paso 5: Crea datos iniciales

```bash
python manage.py shell
```

Dentro de Django shell:

```python
from variables.models import Tenant, Usuario, Proyecto, ConsumoCloud
from datetime import datetime

# Crear tenants
t_a = Tenant.objects.create(key='empresa_a', display_name='Empresa A')
t_b = Tenant.objects.create(key='empresa_b', display_name='Empresa B')

# Crear proyectos
p1 = Proyecto.objects.create(tenant=t_a, name='Proyecto AWS', description='Cloud')
p2 = Proyecto.objects.create(tenant=t_b, name='Proyecto GCP', description='Google Cloud')

# Crear usuarios
u1 = Usuario.objects.create(tenant=t_a, username='user_a', email='user_a@empresa_a.com', role='admin')
u2 = Usuario.objects.create(tenant=t_b, username='user_b', email='user_b@empresa_b.com', role='user')

# Crear consumos de ejemplo
c1 = ConsumoCloud.objects.create(
    tenant=t_a,
    recurso='EC2',
    cantidadUtilizadas=10,
    costoPorUnidad=0.5,
    fechaRegistro=datetime.now(),
    proyecto=p1
)
c1.hash_sha256 = c1.compute_hash()
c1.save()

print("✓ Datos iniciales creados")
exit()
```

---

## Paso 6: Prueba endpoints

```bash
# Health check (para ALB)
curl http://localhost:8000/health
curl http://localhost:8000/health?db=1

# Prueba tenant middleware (si ejecutas en modo debug)
curl -H "X-Tenant: empresa_a" http://localhost:8000/

# Prueba management command
python manage.py validate_and_publish_checksums --tenant empresa_a --year 2026 --month 5
```

---

## Paso 7: Crea bucket S3 y sube hashes

```bash
# Crear bucket S3
aws s3 mb s3://hashes-inmutables --region us-east-1

# (Opcional) Habilitar Object Lock para inmutabilidad
aws s3api put-object-lock-configuration \
  --bucket hashes-inmutables \
  --object-lock-configuration 'ObjectLockEnabled=Enabled,Rule={DefaultRetention={Mode=GOVERNANCE,Days=365}}'

# Ejecutar management command (sube checksums a S3)
python manage.py validate_and_publish_checksums --tenant empresa_a --year 2026 --month 5

# Verificar upload
aws s3 ls s3://hashes-inmutables/
```

---

## Resumen de Comandos (atajo rápido)

```bash
# En CloudShell

# 1. Clone y configura
cd ~
git clone https://github.com/ISIS2503/ISIS2503-MonitoringApp.git
cd ISIS2503-MonitoringApp

# 2. Terraform (si vas a usar RDS)
cd terraform/environments/dev
terraform init
terraform apply  # → responde: yes
export RDS_HOST=$(terraform output -raw rds_endpoint)
cd ~/ISIS2503-MonitoringApp

# 3. Django
pip install -r requirements.txt boto3 PyJWT
export RDS_HOST=...  # del step anterior
export RDS_USER=postgres
export RDS_PASSWORD=...
export RDS_DB=monitoring_db
python manage.py migrate

# 4. Datos iniciales
python manage.py shell
# → correr scripts de arriba

# 5. Prueba
python manage.py runserver 0.0.0.0:8000
# En otra terminal:
curl http://localhost:8000/health
```

---

## Troubleshooting

### Error: "Terraform not found"
```bash
# Instala terraform
curl https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip -o tf.zip
unzip tf.zip
sudo mv terraform /usr/local/bin/
terraform --version
```

### Error: "No credentials found"
```bash
# CloudShell ya tiene credenciales. Si falla:
aws sts get-caller-identity

# Si no funciona, ve a AWS IAM y crea una clave de acceso
```

### Error: "RDS connection refused"
```bash
# Verifica que RDS esté en estado "available"
aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'

# Verifica security group permite puerto 5432 desde CloudShell
aws ec2 describe-security-groups --group-names monitoring-app-db-sg
```

### Error: "S3 bucket already exists"
```bash
# Bucket S3 ya existe (posiblemente de despliegue anterior)
# Usa otro nombre:
export S3_BUCKET_HASHES=hashes-inmutables-$(date +%s)
aws s3 mb s3://$S3_BUCKET_HASHES
```

---

## ¿Cuánto cuesta?

**Aprox. con Terraform en dev:**
- RDS t3.micro: ~$15/mes (dev), ~$40/mes (prod Multi-AZ)
- EC2 t3.micro: ~$10/mes
- ALB: ~$16/mes
- **Total dev:** ~$40/mes

**Cómo detener costos:**
```bash
# Destruir todo (ATENCION: borra recursos)
cd terraform/environments/dev
terraform destroy  # → responde: yes
```

---

## Próximos pasos después de desplegar

1. ✅ Terraform creó infraestructura
2. ✅ Django conecta a RDS
3. ✅ Migraciones aplicadas
4. ✅ Tests ejecutados
5. Próximo: Configurar CI/CD (GitHub Actions, CodePipeline, etc.)
6. Próximo: Monitoreo en CloudWatch
7. Próximo: Configurar ALB health checks en la consola AWS

¿Necesitas ayuda con algún paso específico?
