# Experimentos ASR adaptados a tu arquitectura

Este documento resume los tres experimentos que quieres presentar, usando la infraestructura y los diagramas que compartiste, pero alineados con el código que ya existe en el repositorio.

## 1. ASR - Disponibilidad

### Título del experimento - Disponibilidad

Prueba de recuperación automática ante fallo de servidor.

### ASR involucrado - Disponibilidad

"Yo, como usuario de la plataforma, cuando esté en operación normal y el sistema presente una falla en un servidor, quiero que el tiempo de recuperación ante una caída no supere los 5 segundos."

### Infraestructura que lo soporta - Disponibilidad

- `module.availability` en `terraform/environments/dev/main.tf` y `terraform/environments/prod/main.tf`.
- Application Load Balancer con health checks rápidos.
- Auto Scaling Group con mínimo 2 instancias.
- Instancias EC2 con el servidor de usuarios Django.
- Base de datos RDS PostgreSQL.
- JMeter para simular carga.

### Cómo se ve en tu diagrama - Disponibilidad

- Usuario cliente -> ALB -> dos instancias del servidor de usuarios.
- Una instancia se detiene durante la prueba.
- El ALB deja de enrutar tráfico a la instancia caída y conserva el servicio con la otra instancia sana.

### Variables que debes ajustar - Disponibilidad

- `asg_min_size = 2`
- `asg_max_size = 6`
- `asg_desired_capacity = 2` o `3`
- `instance_type = "t3.medium"` o el tamaño que definas para tu demo.
- `enable_https = true` si vas a mostrar la versión final.
- `certificate_arn` si usarás HTTPS real.

### Métrica de éxito - Disponibilidad

- Failover menor o igual a 5 segundos.
- Pérdida de peticiones menor al 1%.

### Pruebas del repo relacionadas - Disponibilidad

- [tests/availability_tests/test_availability.py](../tests/availability_tests/test_availability.py)

## 2. ASR - Confidencialidad

### Título del experimento - Confidencialidad

Prueba de aislamiento de datos entre empresas clientes.

### ASR involucrado - Confidencialidad

"Yo, como sistema, ante un intento de acceso no autorizado a datos de otra empresa, quiero bloquear el acceso y garantizar que no se exponga información de terceros en el 100% de los casos."

### Infraestructura que lo soporta - Confidencialidad

- `module.confidentiality`.
- `module.proxysql` para el enrutamiento por tenant.
- WAF en el balanceador.
- Security Groups restrictivos.
- RDS PostgreSQL con cifrado y SSL.
- VPC Flow Logs y CloudWatch para auditoría.
- Auth0 como puerta de autenticación, si lo incluyes en la demo.

### Cómo se ve en tu diagrama - Confidencialidad

- Usuario cliente -> ALB -> servidor de usuarios -> ProxySQL -> esquema o BD de la empresa correcta.
- Si el Usuario_A intenta consultar Empresa_B, la solicitud debe ser bloqueada y registrada.

### Variables que debes ajustar - Confidencialidad

- `allowed_ssh_cidrs` para que SSH no quede público.
- `admin_cidrs` para limitar administración.
- `blocked_ip_list` para IPs maliciosas.
- `db_username` y `db_password` como secretos reales por entorno.

### Métrica de éxito - Confidencialidad

- 100% de intentos cruzados bloqueados.
- 0 exposición de datos de otra empresa.
- Incidente registrado en logs de auditoría.

### Pruebas del repo relacionadas - Confidencialidad

- [tests/confidentiality_tests/test_confidentiality.py](../tests/confidentiality_tests/test_confidentiality.py)

## 3. ASR - Integridad

### Título del experimento - Integridad

Prueba de detección de manipulación de datos para reportes de costos.

### ASR involucrado - Integridad

"Yo, como sistema, ante un intento de alteración de datos en los reportes de costos cloud, quiero detectar y rechazar datos modificados antes de la generación del reporte en el 100% de los casos."

### Infraestructura que lo soporta - Integridad

- `module.integrity`.
- DynamoDB para audit trail y checksums.
- Lambda para validación de integridad.
- EventBridge para ejecutar la validación periódica.
- S3 con Object Lock para almacenar hashes inmutables.
- KMS para cifrado.
- La app Django del monolito para generar el reporte.

### Cómo se ve en tu diagrama - Integridad

- Servidor de datos o manejador de reportes calcula hash SHA-256.
- El hash se guarda en almacenamiento inmutable.
- Si alguien modifica la base de datos, el reporte debe rechazarse antes de emitirse.

### Variables que debes ajustar - Integridad

- `db_endpoint`
- `db_username`
- `db_password`
- `source_db_arn`
- En la app Django:
  - `ENABLE_HASH_UPLOAD=1`
  - `S3_BUCKET_HASHES=<tu_bucket>`
  - `DEFAULT_TENANT=public` o el tenant que corresponda

### Métrica de éxito - Integridad

- 100% de modificaciones detectadas.
- El reporte no se genera si hay inconsistencia.
- Se registra el incidente en auditoría y se emite alerta.

### Pruebas del repo relacionadas - Integridad

- [tests/integrity_tests/test_integrity.py](../tests/integrity_tests/test_integrity.py)
- [tests/integrity_tests/test_consume_integrity.py](../tests/integrity_tests/test_consume_integrity.py)
- [measurements/logic/logic_measurement.py](../measurements/logic/logic_measurement.py)
- [measurements/models.py](../measurements/models.py)

## Variables por entorno

### Desarrollo

Usa valores pequeños para no subir costos:

- `instance_type = "t3.medium"`
- `asg_min_size = 2`
- `asg_max_size = 6`
- `asg_desired_capacity = 2`
- `log_retention_days = 7`
- `enable_https = false` si estás probando localmente

### Producción o demo formal

Usa valores más estrictos:

- `instance_type = "t3.large"`
- `asg_min_size = 2`
- `asg_max_size = 6`
- `asg_desired_capacity = 3`
- `log_retention_days = 90`
- `enable_https = true`
- `admin_cidrs` restringido a tu red administrativa

## Recomendación para tu entrega

Si tu objetivo es presentar un trabajo claro y consistente, usa este orden:

1. Disponibilidad.
2. Confidencialidad.
3. Integridad.

La integridad te conviene como experimento principal porque ya tienes código de hashing y validación en el monolito, y además es más fácil demostrar el rechazo de datos manipulados sin depender de una caída real de infraestructura.
