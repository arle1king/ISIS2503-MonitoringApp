# Guía de Inicio Rápido - Infraestructura Terraform

## 📋 Checklist Pre-Despliegue

Antes de desplegar, asegúrate de tener:

- [ ] Terraform instalado (`terraform version`)
- [ ] AWS CLI configurado (`aws sts get-caller-identity`)
- [ ] Python 3.8+ instalado (`python --version`)
- [ ] Permisos en AWS para crear: VPC, EC2, RDS, DynamoDB, Lambda, WAF

## 🚀 Despliegue Rápido en Development

### 1. Clonar y navegar al directorio
```bash
cd terraform/environments/dev
```

### 2. Validar configuración
```bash
python ../../validate.py
```

Esperado:
```
✓ Terraform instalado
✓ AWS credentials OK
✓ AWS region configurada
✓ Terraform syntax OK
```

### 3. Inicializar Terraform
```bash
terraform init
```

Esto descarga los providers necesarios (AWS).

### 4. Revisar plan
```bash
terraform plan
```

Verifica que va a crear/modificar:
- 1 VPC con 6 subnets
- 1 ALB con health checks
- 1 Auto Scaling Group
- 1 RDS Multi-AZ
- 1 WAF con reglas
- 2 DynamoDB tables
- 1 Lambda function
- 1 EventBridge rule
- Y muchos recursos más...

### 5. Aplicar configuración
```bash
terraform apply
```

Escribe `yes` cuando pregunte. Espera ~10-15 minutos.

### 6. Obtener outputs
```bash
terraform output
```

Guardará información importante:
- ALB DNS Name
- RDS Endpoint
- WAF ARN
- Tabla de auditoría

## ✅ Ejecutar Tests

### Instalar dependencias de tests
```bash
pip install -r requirements-test.txt
```

### Ejecutar todos los tests
```bash
cd ../..
pytest tests/ -v
```

### Ejecutar tests específicos
```bash
# Solo disponibilidad
pytest tests/availability_tests/ -v

# Solo confidencialidad
pytest tests/confidentiality_tests/ -v

# Solo integridad
pytest tests/integrity_tests/ -v

# Test específico
pytest tests/availability_tests/test_availability.py::TestAvailability::test_alb_health_check_configuration -v
```

## 📊 Monitorear en AWS Console

Acceder a:
1. **EC2 Dashboard**: Ver instancias en ASG
2. **Load Balancer**: Ver ALB y health checks
3. **RDS**: Ver base de datos Multi-AZ
4. **DynamoDB**: Ver audit trail table
5. **CloudWatch**: Ver dashboards y logs

```
https://console.aws.amazon.com/console/home
```

## 🔧 Troubleshooting

### "terraform: command not found"
```bash
# Instalar Terraform
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### "InvalidParameterException: No default VPC"
```bash
# Necesitas crear una VPC o usar una existente
# Actualizar terraform.tfvars con VPC ID
```

### "AuthFailure: User is not authorized"
```bash
# Verificar credenciales AWS
aws sts get-caller-identity
# Verificar permisos IAM en AWS Console
```

### Tests fallan con "Connection refused"
```bash
# Esperar a que infraestructura esté lista
# Ver logs en CloudWatch
# Verificar security groups
```

## 📝 Archivos Importantes

- `terraform/modules/common/main.tf` - VPC y networking
- `terraform/modules/availability/main.tf` - ALB, ASG, RDS
- `terraform/modules/confidentiality/main.tf` - WAF, encriptación
- `terraform/modules/integrity/main.tf` - DynamoDB, Lambda
- `terraform/environments/dev/main.tf` - Configuración dev
- `terraform/environments/prod/main.tf` - Configuración prod
- `tests/availability_tests/test_availability.py` - Tests disponibilidad
- `tests/confidentiality_tests/test_confidentiality.py` - Tests seguridad
- `tests/integrity_tests/test_integrity.py` - Tests integridad

## 🗑️ Destruir Infraestructura

Cuando termines (para no gastar dinero):

```bash
cd terraform/environments/dev
terraform destroy
```

Escribe `yes` cuando confirme.

## 📚 Documentación Completa

- [ASR Disponibilidad](../docs/ASR_Disponibilidad.md)
- [ASR Confidencialidad](../docs/ASR_Confidencialidad.md)
- [ASR Integridad](../docs/ASR_Integridad.md)
- [Terraform README](../terraform/README.md)

## 💡 Tips

1. **Guardar outputs**: `terraform output > outputs.txt`
2. **Ver estado**: `terraform show`
3. **Plan detallado**: `terraform plan -json > plan.json`
4. **Validar syntax**: `terraform fmt -check`
5. **Destruir selectivamente**: `terraform destroy -target=aws_instance.example`

## 🆘 Soporte

Para problemas específicos, revisar:
1. Documentación en `/docs/`
2. Terraform logs: `terraform apply -lock=false`
3. AWS CloudWatch Logs
4. Errores de tests: `pytest tests/ -v -s`

---

¡Listo para comenzar! 🎉
