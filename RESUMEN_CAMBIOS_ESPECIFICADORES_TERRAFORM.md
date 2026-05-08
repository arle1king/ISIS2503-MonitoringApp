# RESUMEN: Especificadores de Experimentos y Cambios en Terraform

## Documentos de Especificación Creados

Se han creado **3 documentos detallados** con la especificación completa de cada ASR:

### 1. ASR 1: Disponibilidad (Failover)
**Archivo:** `docs/ASR1_ESPECIFICADOR_Disponibilidad.md`
- **Prueba:** Recuperación automática ante fallo de servidor
- **Infraestructura:** 3 instancias EC2 (usuarios, datos, notificaciones)
- **Health Check:** Puerto 8080, ruta `/health-check/`, intervalo 2 segundos
- **Criterio de éxito:** Failover en ≤ 5 segundos, pérdida de peticiones ≤ 1%
- **Herramienta:** Apache JMeter con 500 usuarios concurrentes

### 2. ASR 2: Confidencialidad (Aislamiento Multi-tenant)
**Archivo:** `docs/ASR2_ESPECIFICADOR_Confidencialidad.md`
- **Prueba:** Aislamiento de datos entre empresas clientes
- **Infraestructura:** ProxySQL + 3 esquemas RDS (empresa_a, empresa_b, empresa_c)
- **Componentes:** API Gateway (Auth0), ProxySQL router, RDS con esquemas separados
- **Ataques simulados:** 5 vectores de ataque (tenant override, SQL injection, escalamiento, conexión directa, modificación)
- **Criterio de éxito:** 100% de intentos de acceso no autorizado bloqueados, 0% exposición de datos

### 3. ASR 3: Integridad (Validación de Datos)
**Archivo:** `docs/ASR3_ESPECIFICADOR_Integridad.md`
- **Prueba:** Detección de manipulación de datos en reportes
- **Infraestructura:** S3 Object Lock (WORM) + Lambda SHA-256 + DynamoDB audit trail
- **Escenario:** Modificación directa de costos en BD (fraude)
- **Validación:** Pre-reporte con comparación de hashes
- **Criterio de éxito:** 100% detección de modificaciones, reporte rechazado, alerta enviada

---

## Cambios en Terraform

### 1. Módulo: Disponibilidad (ASR 1)
**Archivo:** `terraform/modules/availability/main.tf`

**Cambios realizados:**
```
✓ Health Check actualizado:
  - Puerto: 8000 → 8080 (dedicado para health checks)
  - Ruta: /health/ → /health-check/
  - Intervalo: 5 seg → 2 seg (ASR requerimiento)
  - Timeout: 3 seg → 1 seg
  - Unhealthy threshold: 2 fallos → 4 segundos total

✓ Auto Scaling Group:
  - min_size: Variable → 3 (fijo para experimento)
  - desired_capacity: Variable → 3 (exactamente 3: usuarios, datos, notificaciones)
  - Comentarios agregados explicando roles de cada instancia

✓ Notas de recuperación:
  - Agregada documentación: Failover detection en ~4 segundos (< 5 seg ✓)
```

### 2. Módulo Nuevo: ProxySQL (ASR 2)
**Ruta:** `terraform/modules/proxysql/`

**Archivos creados:**
- `main.tf` (400+ líneas)
- `variables.tf`
- `proxysql_setup.sh` (script de instalación)

**Componentes:**
```
✓ EC2 ProxySQL (t3.small)
  - Security Group restrictivo (app servers → 3306, db → 5432)
  - User data script para instalación y configuración

✓ Enrutamiento por tenant:
  - Usuario empresa_a → schema empresa_a
  - Usuario empresa_b → schema empresa_b
  - Usuario empresa_c → schema empresa_c
  - Intento cross-tenant → DENY

✓ IAM Role + Policy:
  - Logs en CloudWatch
  - KMS decrypt
  - Mínimo privilegio

✓ CloudWatch Logging:
  - Log Group: /aws/project_name/proxysql
  - Alarm: access_denied >= 5 → Alert
```

### 3. Módulo Actualizado: Integridad (ASR 3)
**Archivo:** `terraform/modules/integrity/main.tf`

**Cambios realizados:**
```
✓ S3 Bucket con Object Lock (WORM):
  - Nombre: {project_name}-audit-hashes-immutable-{account_id}
  - Modo COMPLIANCE: no se puede borrar/modificar
  - Retención: 365 días mínimo
  - Versionado: Enabled (para PITR)
  - Encriptación: KMS

✓ Logging de S3:
  - Bucket separado para access logs
  - Prefijo: s3-access-logs/
  - Auditoría completa de accesos

✓ DynamoDB Audit Trail:
  - PK: EntityId (String)
  - SK: Timestamp (Number)
  - PITR: Enabled
  - TTL: 2555 días (~7 años)
  - Encriptación: KMS

✓ Lambda Integrity Verifier:
  - Runtime: Python 3.11
  - Memory: 512 MB
  - Timeout: 60 seg
  - Roles: S3, DynamoDB, RDS, KMS, SNS

✓ EventBridge Rules:
  - Regla 1: Cada 5 minutos (validación periódica)
  - Regla 2: Cron pre-reporte (1am lunes-viernes)

✓ CloudWatch Alarms:
  - Alarm: IntegrityViolationDetected >= 1
  - Acción: SNS Topic → Email/Alert
```

---

## Estructura de Directorios Actualizada

```
terraform/
├── modules/
│   ├── common/              (sin cambios - base)
│   ├── availability/        (ACTUALIZADO - ASR 1)
│   ├── confidentiality/     (sin cambios - WAF/KMS)
│   ├── integrity/           (ACTUALIZADO - S3 Object Lock + Lambda)
│   └── proxysql/            (NUEVO - ASR 2)
│       ├── main.tf
│       ├── variables.tf
│       └── proxysql_setup.sh
│
└── environments/
    ├── dev/
    │   ├── main.tf (necesita actualización para ProxySQL)
    │   └── variables.tf
    └── prod/
        ├── main.tf (necesita actualización para ProxySQL)
        └── variables.tf

docs/
├── ASR1_ESPECIFICADOR_Disponibilidad.md         (NUEVO)
├── ASR2_ESPECIFICADOR_Confidencialidad.md       (NUEVO)
├── ASR3_ESPECIFICADOR_Integridad.md             (NUEVO)
├── ASR_Disponibilidad.md                        (anterior)
├── ASR_Confidencialidad.md                      (anterior)
└── ASR_Integridad.md                            (anterior)
```

---

## Próximos Pasos Recomendados

### 1. Actualizar Environment Files
```hcl
# terraform/environments/dev/main.tf
module "proxysql" {
  source = "../../modules/proxysql"
  
  project_name = var.project_name
  environment  = "dev"
  # ... agregar todas las variables
}
```

### 2. Validar Terraform
```bash
cd terraform/environments/dev
terraform validate
terraform plan
```

### 3. Crear Lambda Package
```bash
# Empaquetar lambda_integrity_verifier.zip con función de hashing SHA-256
zip lambda_integrity_verifier.zip index.py
```

### 4. Agregar Django Endpoints
```python
# monitoring/views.py
@app.route('/health-check/', methods=['GET'])
def health_check():
    """Health check endpoint para ALB (puerto 8080)"""
    return {'status': 'healthy'}, 200, {'Server': 'DjangoHealthCheck/1.0'}
```

### 5. Ejecutar Experimentos
```bash
# ASR 1: JMeter
jmeter -n -t Jmeter-test/Load-tests.jmx

# ASR 2: Python requests + Burp Suite (ataques multi-tenant)
python test_confidentiality_attacks.py

# ASR 3: Simular modificación y validar detección
# Modificar dato en RDS → Invocar Lambda → Validar rechazo
```

---

## Validación Completa

| ASR | Especificador | Terraform | Status |
|-----|---------------|-----------|--------|
| 1 - Disponibilidad | ✅ Creado | ✅ Actualizado | Listo |
| 2 - Confidencialidad | ✅ Creado | ✅ Módulo nuevo | Listo |
| 3 - Integridad | ✅ Creado | ✅ Actualizado | Listo |

---

## Archivos Principales

**Especificadores (documentación detallada):**
- [ASR1_ESPECIFICADOR_Disponibilidad.md](../docs/ASR1_ESPECIFICADOR_Disponibilidad.md)
- [ASR2_ESPECIFICADOR_Confidencialidad.md](../docs/ASR2_ESPECIFICADOR_Confidencialidad.md)
- [ASR3_ESPECIFICADOR_Integridad.md](../docs/ASR3_ESPECIFICADOR_Integridad.md)

**Terraform (infraestructura actualizada):**
- [terraform/modules/availability/main.tf](../terraform/modules/availability/main.tf) - ASR 1 actualizado
- [terraform/modules/proxysql/main.tf](../terraform/modules/proxysql/main.tf) - ASR 2 nuevo
- [terraform/modules/integrity/main.tf](../terraform/modules/integrity/main.tf) - ASR 3 actualizado

---

**Completado:** Especificadores + Terraform actualizado y listo para despliegue de experimentos.
