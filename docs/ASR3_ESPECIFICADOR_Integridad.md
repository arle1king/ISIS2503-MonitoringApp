# ASR 3: Integridad (Validación de Datos)
## Prueba de detección de manipulación de datos para reportes de costos

### ASR Involucrado
**Yo, como sistema, ante un intento de alteración de datos en los reportes de costos cloud (ataque de manipulación de información), dado que se generan reportes mensuales, quiero detectar y rechazar datos modificados antes de la generación del reporte en el 100% de los casos.**

### Propósito del Experimento
Evaluar si la arquitectura con verificador de integridad (hashing/firma digital) es capaz de detectar datos manipulados en la base de datos antes de generar un reporte de costos cloud.

### Resultados Esperados
Se espera que, ante una modificación directa de datos en la base de datos (por atacante interno o externo), el sistema **detecte la alteración mediante la validación de hash y rechace la generación del reporte en el 100% de los casos**, notificando al administrador.

### Infraestructura Computacional Requerida

| Componente | Especificación | Cantidad | Detalle |
|-----------|----------------|---------| --------|
| **EC2 - Servidor de Datos** | t3.medium Ubuntu 22.04 | 1 | Django + lógica de reportes |
| **EC2 - Manejador de Reportes** | t3.small Ubuntu 22.04 | 1 | Lambda o script cron para reportes |
| **Base de Datos** | AWS RDS PostgreSQL 15.3 | 1 | Almacenamiento de costos |
| **Verificador de Integridad** | AWS Lambda / Microservicio | 1 | SHA-256 hashing y validación |
| **Almacenamiento Inmutable** | AWS S3 con Object Lock | 1 | WORM (Write-Once-Read-Many) para hashes |
| **Vault de Firmas** | AWS KMS o HashiCorp Vault | 1 | Gestión de claves y firmas digitales |
| **CloudWatch Logs** | AWS CloudWatch | 1 | Auditoría de operaciones |
| **SNS Notifications** | AWS SNS | 1 | Alertas al administrador |
| **Computador Personal** | SQL client + Python | - | Simulación de ataques |

### Configuración de Almacenamiento Inmutable

```yaml
S3 Bucket Configuration:
  Bucket Name: monitoring-app-audit-hashes-immutable
  Versioning: Enabled (para PITR si es necesario)
  Object Lock:
    Enabled: true
    Retention Mode: COMPLIANCE (no se puede borrar ni modificar)
    Retention Period: 365 days (mínimo)
    Legal Hold: Enabled (para casos de forensics)
  
  Structure:
    /costos/YYYY/MM/DD/report_id_hash.json
    
  Example:
    /costos/2024/01/15/RPT-2024-01-001/
      - hash_record_1.json
      - hash_record_2.json
      - checksum_manifest.json (contiene SHA-256 de todos los hashes)
```

### Configuración de Lambda Verificador de Integridad

```python
Lambda Function: data_integrity_verifier
Runtime: Python 3.11
Memory: 512 MB
Timeout: 60 seconds

Environment Variables:
  - S3_BUCKET: monitoring-app-audit-hashes-immutable
  - RDS_ENDPOINT: monitoring-app.c9akciq32.us-east-1.rds.amazonaws.com
  - KMS_KEY_ID: arn:aws:kms:us-east-1:ACCOUNT:key/KEY_ID
  - SNS_TOPIC_ARN: arn:aws:sns:us-east-1:ACCOUNT:integrity-alerts

Permissions:
  - s3:GetObject, s3:PutObject (audit-hashes bucket)
  - rds-db:connect (RDS database)
  - kms:Decrypt, kms:GenerateDataKey
  - logs:CreateLogGroup, logs:PutLogEvents
  - sns:Publish
```

### Descripción del Experimento

#### Fase 1: Preparación e Inicialización

1. **Crear tabla de costos en RDS:**
```sql
CREATE TABLE costos (
  id SERIAL PRIMARY KEY,
  empresa_id VARCHAR(50),
  servicio VARCHAR(50),  -- EC2, RDS, S3, Lambda, etc.
  amount DECIMAL(10, 2),
  fecha_consumo DATE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Datos iniciales:
INSERT INTO costos (empresa_id, servicio, amount, fecha_consumo) VALUES
  ('empresa_a', 'EC2', 100.00, '2024-01-15'),
  ('empresa_a', 'RDS', 50.00, '2024-01-15'),
  ('empresa_a', 'S3', 25.00, '2024-01-15');
-- TOTAL: 175.00
```

2. **Generar hash inicial (SHA-256) de los datos:**
```python
# Integrity Verifier lambda calcula:
data = {
  "fecha_reporte": "2024-01-15",
  "records": [
    {"id": 1, "empresa_id": "empresa_a", "servicio": "EC2", "amount": 100.00},
    {"id": 2, "empresa_id": "empresa_a", "servicio": "RDS", "amount": 50.00},
    {"id": 3, "empresa_id": "empresa_a", "servicio": "S3", "amount": 25.00}
  ],
  "total": 175.00
}

hash_inicial = SHA256(json.dumps(data, sort_keys=True))
# hash_inicial = "abc123def456..."

# Almacenar en S3 (immutable):
s3_key = f"costos/2024/01/15/RPT-2024-01-001_hash.json"
s3.put_object(
  Bucket="monitoring-app-audit-hashes-immutable",
  Key=s3_key,
  Body=json.dumps({
    "hash": "abc123def456...",
    "timestamp": "2024-01-15T10:00:00Z",
    "total": 175.00
  }),
  ServerSideEncryption="aws:kms",
  SSEKMSKeyId=KMS_KEY_ID
)
```

3. **Verificar integridad inicial (pre-reporte):**
- Lambda consulta RDS
- Calcula hash actual
- Compara con hash en S3
- Si coinciden → REPORT_APPROVED ✓

#### Fase 2: Simulación de Ataque (Modificación de Datos)

**Atacante: DBA insider o SQL injection bypass**

```sql
-- Atacante modifica directamente en RDS (sin pasar por app):
UPDATE costos SET amount = 10000.00 WHERE id = 1 AND servicio = 'EC2';
-- Intenta cubrir la pista:
UPDATE costos SET updated_at = '2024-01-15T10:00:00Z' WHERE id = 1;

-- NUEVO TOTAL: 10,050.00 (en lugar de 175.00)
```

**Datos modificados en BD:**
```
EC2: 100.00 → 10,000.00 (+ 9,900.00 fraudulento)
```

#### Fase 3: Intento de Generación de Reporte

1. **Usuario legítimo solicita reporte:**
```
POST /api/reports/generate
Body:
{
  "fecha_inicio": "2024-01-15",
  "fecha_fin": "2024-01-15",
  "empresa_id": "empresa_a"
}
```

2. **App Server invoca Lambda verificador:**
```python
# App Server code:
lambda_client.invoke(
  FunctionName="data_integrity_verifier",
  InvocationType="RequestResponse",
  Payload=json.dumps({
    "fecha_reporte": "2024-01-15",
    "empresa_id": "empresa_a",
    "action": "VALIDATE_BEFORE_REPORT"
  })
)
```

3. **Lambda valida integridad:**
```python
# Lambda code (simplified):

def validate_integrity(fecha_reporte):
  # 1. Consultar datos actuales de RDS
  data_actual = query_rds(f"SELECT * FROM costos WHERE fecha_consumo = '{fecha_reporte}'")
  
  # 2. Calcular hash actual
  hash_actual = SHA256(json.dumps(data_actual, sort_keys=True))
  # hash_actual = "xyz789abc..."  ← DIFERENTE al inicial
  
  # 3. Obtener hash almacenado de S3 (immutable)
  hash_stored = s3.get_object(f"costos/2024/01/15/RPT-2024-01-001_hash.json")
  # hash_stored = "abc123def456..."  ← INICIAL
  
  # 4. Comparar
  if hash_actual != hash_stored:
    # INTEGRIDAD COMPROMETIDA
    log_event("INTEGRITY_VIOLATION", {
      "fecha_reporte": fecha_reporte,
      "hash_expected": hash_stored,
      "hash_actual": hash_actual,
      "differences": calculate_diff(data_stored, data_actual),
      "severity": "CRITICAL"
    })
    
    # 5. Rechazar reporte
    send_sns_alert({
      "subject": "ALERTA CRÍTICA: Manipulación de Datos Detectada",
      "message": f"Datos de costos del {fecha_reporte} han sido alterados.",
      "admin_email": "admin@empresa.com"
    })
    
    return {
      "status": "REJECTED",
      "reason": "DATA_INTEGRITY_VIOLATION",
      "error": "Reporte rechazado. Diferencia detectada en datos.",
      "timestamp": NOW()
    }
  
  else:
    # Integridad OK
    return {
      "status": "APPROVED",
      "reason": "Hash validation passed",
      "can_generate_report": true
    }
```

4. **Resultado del Intento:**
```
Lambda Response:
{
  "status": "REJECTED",
  "reason": "DATA_INTEGRITY_VIOLATION",
  "error": "Reporte rechazado. Diferencia detectada en datos.",
  "differences": {
    "field": "amount",
    "record_id": 1,
    "expected": 100.00,
    "actual": 10000.00
  },
  "timestamp": "2024-01-15T15:30:45Z"
}

App Server:
- NO genera reporte
- Registra incidente en logs
- Devuelve error 403 al usuario
- Envía SNS alert a admin
```

#### Fase 4: Validación de Resultados

**Validación 1: Reporte NO se generó** ✓
- Verificar que reporte no existe en bucket de reportes
- Verificar que fecha_generado no existe en tabla reports

**Validación 2: Alerta fue enviada** ✓
- Verificar email de admin
- Verificar SNS topic logs

**Validación 3: Incidente fue registrado** ✓
- Consultar CloudWatch Logs
- Buscar entrada de INTEGRITY_VIOLATION

**Validación 4: Datos modificados están en auditoría** ✓
```sql
SELECT * FROM CloudWatch Logs WHERE event = 'INTEGRITY_VIOLATION'
LIMIT 1;
-- Debe contener: fecha_reporte, differences, severity=CRITICAL
```

### Criterios de Éxito (100% de casos)

✅ **PASS si:**
- 100% de modificaciones de datos son detectadas
- 100% de reportes con datos alterados son rechazados
- 100% de incidentes son registrados en audit logs
- 100% de alertas al admin son enviadas
- Cero reportes fraudulentos son generados
- No hay datos modificados presentes en el reporte rechazado

❌ **FAIL si:**
- Reporte se genera a pesar de data tampering (1 fallo = 100% failure)
- Modificación no es detectada
- Alerta no se envía
- Incidente no se registra
- Hash detection falla

### Monitoreo y Observabilidad

```
CloudWatch Metrics:
- integrity_check_runs (contador)
- integrity_violations_detected (contador)
- hash_mismatches (contador)
- reports_rejected_for_integrity (contador)
- reports_approved_after_validation (contador)

CloudWatch Alarms:
- integrity_violations_detected >= 1 → CRITICAL
- reports_rejected >= 1 → ALERT
- hash_mismatch_rate > 0% → CRITICAL

Lambda Metrics:
- Execution Count
- Duration (ms)
- Errors
- Throttles
```

### Auditoría y Registro

```
S3 Immutable Log Structure:
/costos/YYYY/MM/DD/report_id/
  ├── hash_record.json (SHA-256 con Object Lock)
  ├── checksum_manifest.json (lista de hashes)
  └── metadata.json (timestamp, actor, etc.)

CloudWatch Logs:
- /aws/lambda/data_integrity_verifier
  - Each execution: validation result
  - Violations: detailed diff
  - Timestamps: UTC ISO-8601

DynamoDB Audit Trail (opcional pero recomendado):
- PK: ReportId
- SK: Timestamp
- Attributes: validation_result, hash_expected, hash_actual, differences
```

### Recuperación Post-Experimento

1. Revertir cambios en RDS a valores originales
2. Verificar que siguiente validación pasa
3. Generar reporte nuevamente (debe aprobar)
4. Confirmar que reporte tiene total original (175.00)
5. Limpiar logs de prueba

### Notas Técnicas

- S3 Object Lock en COMPLIANCE mode = no se puede borrar (incluso admin root no puede)
- Hash debe incluir timestamp para evitar colisiones
- Lambda debe ejecutar cada 5 minutos (pre-reporte) y también on-demand
- Considerar encripción KMS + customer-managed key
- Bucket S3 debe tener versionado + logging
- Alerts deben ir a múltiples canales (email + Slack + PagerDuty)
- Mantener audit trail durante mínimo 1 año (compliance)
