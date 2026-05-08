# ASR: Integridad
## Detectar y Rechazar Datos Modificados (100%)

### 1. Descripción

**Requisito de Negocio:**
> Yo como sistema, ante un intento de alteración de datos en los reportes de costos cloud (ataque de manipulación de información), dado que se generan reportes mensuales, quiero detectar y rechazar datos modificados antes de la generación del reporte en el 100% de los casos.

**Objetivo:**
Garantizar que 100% de intentos de modificación de datos en reportes de costos sean detectados y rechazados ANTES de que el reporte se genere. Mantener auditoría inmutable de todos los cambios.

### 2. Componentes de Infraestructura

#### 2.1 Change Data Capture (CDC)
- **Method**: Triggers en PostgreSQL + DynamoDB audit trail
- **Every Change**: INSERT, UPDATE, DELETE registrado
- **Metadata Captured**: User, timestamp, old value, new value, checksum

#### 2.2 DynamoDB Tables
```
┌─────────────────────────────────────────────┐
│ monitoring-app-audit-trail                  │
├─────────────────────────────────────────────┤
│ PK: EntityId (String)                       │
│ SK: Timestamp (Number)                      │
│ Attributes:                                  │
│ - Action: CREATE, UPDATE, DELETE            │
│ - Actor: Usuario que hizo el cambio         │
│ - OldValue: JSON anterior                   │
│ - NewValue: JSON nuevo                      │
│ - Checksum: SHA-256 de los datos            │
│ - Status: APPROVED, REJECTED, PENDING       │
│                                              │
│ Features:                                    │
│ - Point-in-time Recovery: ON                │
│ - TTL: 2555 días (7 años)                   │
│ - Encryption: KMS                           │
│ - Billing: On-demand                        │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ monitoring-app-report-checksums             │
├─────────────────────────────────────────────┤
│ PK: ReportId (String)                       │
│ SK: GeneratedAt (Number)                    │
│ Attributes:                                  │
│ - Checksum: SHA-256 of entire report        │
│ - DataSet: Reference to audit entries       │
│ - ApprovedAt: Timestamp de aprobación       │
│ - ApprovedBy: Usuario que aprobó            │
│ - Status: PENDING, APPROVED, REJECTED       │
│ - RejectionReason: Si aplica                │
│                                              │
│ Features:                                    │
│ - Point-in-time Recovery: ON                │
│ - Encryption: KMS                           │
│ - Billing: On-demand                        │
└─────────────────────────────────────────────┘
```

#### 2.3 Lambda Functions

**Function: data_validation**
- **Runtime**: Python 3.11
- **Timeout**: 60 segundos
- **Memory**: 512 MB
- **Trigger**: EventBridge every 5 minutes + on-demand

#### 2.4 EventBridge Rules

```
┌────────────────────────────────────────────────┐
│ Rule: monitoring-app-integrity-check           │
│ - Schedule: rate(5 minutes)                    │
│ - Target: Lambda data_validation              │
│ - Action: Validate data consistency            │
│                                                 │
│ Rule: monitoring-app-pre-report-validation    │
│ - Schedule: cron(0 1 * * MON-FRI *)           │
│ - Target: Lambda data_validation              │
│ - Action: Full integrity check before report   │
└────────────────────────────────────────────────┘
```

### 3. Flujo de Validación de Integridad

```
┌──────────────────────────────────────────────────┐
│ Evento: Cambio en datos de reporte               │
│ (UPDATE en tabla de costos)                      │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼ (T+0)
┌──────────────────────────────────────────────────┐
│ PostgreSQL Trigger: audit_trail_trigger          │
│ - Captura old/new values                         │
│ - Genera checksum SHA-256                        │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼ (T+1s)
┌──────────────────────────────────────────────────┐
│ Escribe en DynamoDB audit_trail                  │
│ - EntityId: cost_report_2024_01                  │
│ - Timestamp: current time                        │
│ - Checksum: abc123def456...                      │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼ (T+5 min - EventBridge)
┌──────────────────────────────────────────────────┐
│ Lambda data_validation ejecuta:                  │
│ 1. Lee todos los cambios desde audit trail       │
│ 2. Valida checksums                              │
│ 3. Detecta modificaciones no autorizadas         │
└────────────────────┬─────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
   ┌─────────┐          ┌─────────────────┐
   │ OK      │          │ ANOMALÍA        │
   │ (100%)  │          │ DETECTADA       │
   └────┬────┘          └────────┬────────┘
        │                        │
        ▼                        ▼
   Status:              Status:
   APPROVED            REJECTED
   ✓ Reporte puede      ✗ Reporte bloqueado
     generarse          × Investigación
                          requerida


┌──────────────────────────────────────────────────┐
│ Pre-Report Generation (mensualmente):            │
│ 1. Obtener datos de período                      │
│ 2. Calcular checksum final                       │
│ 3. Comparar con checksum anterior                │
│ 4. Si diferencia y NO autorizada → REJECT        │
│ 5. Si autorizada → APPROVE y generar             │
└──────────────────────────────────────────────────┘
```

### 4. Pruebas Implementadas

#### 4.1 Configuración de Integridad

**test_dynamodb_audit_trail_exists**
- Valida que tabla audit_trail existe
- Confirma PITR (Point-in-Time Recovery) habilitado
- Verifica encriptación KMS activa
- Valida billing mode on-demand

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrity::test_dynamodb_audit_trail_exists -v
```

**test_dynamodb_checksum_table_exists**
- Confirma tabla report_checksums está presente
- Valida encriptación habilitada
- Verifica structure de tabla

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrity::test_dynamodb_checksum_table_exists -v
```

**test_lambda_validation_function_exists**
- Valida que Lambda function existe
- Confirma runtime Python 3.11
- Verifica timeout >= 60 segundos
- Valida variables de entorno configuradas

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrity::test_lambda_validation_function_exists -v
```

#### 4.2 Orquestación de Validaciones

**test_eventbridge_rules_for_integrity_checks**
- Confirma que EventBridge rules existen
- Valida que están habilitadas (ENABLED)
- Verifica schedule expressions correctas
- Asegura targets están configurados

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrity::test_eventbridge_rules_for_integrity_checks -v
```

#### 4.3 Monitoreo y Alertas

**test_cloudwatch_metric_for_data_modification**
- Valida métrica CloudWatch para modificaciones
- Confirma alarma está configurada
- Verifica threshold >= 1
- Asegura alertas se disparan

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrity::test_cloudwatch_metric_for_data_modification -v
```

#### 4.4 Validación Funcional

**test_checksum_generation**
- Valida que checksums son consistentes
- Genera checksum dos veces del mismo data → debe ser idéntico
- Modifica data y genera nuevo checksum → debe ser diferente
- Confirma que modificaciones se detectan

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrityValidation::test_checksum_generation -v
```

Output esperado:
```
✓ Checksum generado correctamente: abc123def456...
✓ Modificación detectada: xyz789uvw123...
```

**test_audit_trail_entry_structure**
- Valida estructura de entrada de auditoría
- Confirma campos requeridos presentes
- Verifica tipos de datos correctos
- Asegura checksum es SHA-256 (64 chars)

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrityValidation::test_audit_trail_entry_structure -v
```

**test_reject_modified_report_data**
- Simula modificación de reporte
- Genera checksum original
- Modifica datos (ej: TOTAL aumenta)
- Valida que checksum cambia
- Confirma que modificación se detecta

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrityValidation::test_reject_modified_report_data -v
```

Output:
```
✓ Reporte modificado rechazado correctamente
```

#### 4.5 Auditoría e Inmutabilidad

**test_audit_log_immutability**
- Valida que logs no pueden ser modificados
- DynamoDB PITR asegura historicidad
- Confirma que cambios históricos son inmutables
- Verifica que cada acción se registra

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrityAudit::test_audit_log_immutability -v
```

**test_pre_report_generation_validation**
- Simula flujo completo de validación
- 5 pasos: fetch → checksum → compare → authorize → generate
- Todos los pasos deben ser SUCCESS
- Valida que proceso es robusto

```bash
pytest tests/integrity_tests/test_integrity.py::TestIntegrityAudit::test_pre_report_generation_validation -v
```

Output:
```
✓ Pre-report validation flow completado
```

### 5. Ejemplo de Detección de Anomalía

```python
# Datos originales
original = {
    'report_id': 'RPT-2024-01',
    'period': '2024-01',
    'costs': {
        'EC2': 500.25,
        'RDS': 300.00,
        'S3': 700.25
    },
    'total': 1500.50
}

# Intento de manipulación
malicious = {
    'report_id': 'RPT-2024-01',
    'period': '2024-01',
    'costs': {
        'EC2': 500.25,
        'RDS': 300.00,
        'S3': 700.25
    },
    'total': 5000.00  # ← Cambio fraudulento
}

# Checksums
checksum_original = SHA256(original) = "abc123..."
checksum_malicious = SHA256(malicious) = "xyz789..."

# Validación
if checksum_original != checksum_malicious:
    status = "REJECTED"
    alert = "Data integrity violation detected"
    log_audit_entry()
    send_alert_to_admin()
```

### 6. Métricas de Monitoreo

```
CloudWatch Dashboard: monitoring-app-integrity

Métricas principales:
┌──────────────────────────────────────────────────┐
│ Data Modifications Detected                      │
│ - Total changes: 1,250 en últimas 24h            │
│ - Authorized: 1,248                              │
│ - Rejected: 2 (anomalies)                        │
│ - Detection rate: 100% ✓                         │
│                                                   │
│ Audit Trail                                       │
│ - Entries written: 3,500                         │
│ - Checksums verified: 3,500                      │
│ - Integrity violations: 0                        │
│ - PITR status: ENABLED ✓                         │
│                                                   │
│ Report Validation                                │
│ - Reports generated: 12                          │
│ - Pre-validation checks: 12/12 passed            │
│ - Reports rejected: 0                            │
│ - Validation accuracy: 100% ✓                    │
│                                                   │
│ Lambda Execution                                 │
│ - Invocations: 288 (5 min intervals)             │
│ - Errors: 0                                      │
│ - Duration: avg 2.3s, max 5.8s                   │
│ - Success rate: 100% ✓                           │
└──────────────────────────────────────────────────┘
```

### 7. Alertas Configuradas

```
┌──────────────────────────────────────────────────┐
│ Alarma: UnauthorizedDataModification             │
│ - Threshold: >= 1 modification detected          │
│ - Window: 5 minutos                              │
│ - Action: SNS alert CRITICAL                     │
│ - Response: Investigación inmediata              │
│                                                   │
│ Alarma: ChecksumMismatch                         │
│ - Threshold: > 0 mismatches en pre-report        │
│ - Window: 1 minuto                               │
│ - Action: Block report generation                │
│ - Action: SNS alert CRITICAL                     │
│                                                   │
│ Alarma: LambdaExecutionFailure                   │
│ - Threshold: >= 1 failure                        │
│ - Window: 5 minutos                              │
│ - Action: SNS alert para troubleshooting         │
│ - Response: Manual intervention si necesario     │
│                                                   │
│ Alarma: AuditTrailGrowth                         │
│ - Threshold: Unusual spike in entries            │
│ - Window: 15 minutos                             │
│ - Action: Alert para investigación               │
│ - Response: Revisar logs                         │
└──────────────────────────────────────────────────┘
```

### 8. Data Validation Rules

```python
# Reglas de validación que Lambda valida:

VALIDATION_RULES = {
    'cost_fields': {
        'type': 'numeric',
        'min': 0,
        'rule': 'EC2 + RDS + S3 = TOTAL',
        'alert_on_mismatch': True
    },
    'date_fields': {
        'type': 'date',
        'format': 'YYYY-MM-DD',
        'no_future_dates': True,
        'alert_on_mismatch': True
    },
    'enum_fields': {
        'status': ['APPROVED', 'PENDING', 'REJECTED'],
        'alert_on_invalid': True
    },
    'referential_integrity': {
        'company_id_must_exist': True,
        'user_id_must_exist': True,
        'alert_on_orphan': True
    },
    'business_rules': {
        'monthly_reports_only': True,
        'no_duplicate_reports': True,
        'no_future_reports': True,
        'alert_on_violation': True
    }
}
```

### 9. Procedimiento de Rechazo de Reporte

```
Evento: Intento de generar reporte con datos inconsistentes

1. Pre-Report Validation (T-0)
   ├─ Obtener datos del período
   ├─ Validar completitud (todas las columnas)
   ├─ Calcular checksum SHA-256
   └─ Comparar con checksum anterior

2. Anomaly Detection (T-1s)
   ├─ Buscar modificaciones en audit trail
   ├─ Validar que todos cambios están autorizados
   ├─ Verificar integridad referencial
   └─ Revisar business rules

3. Decision Logic
   ├─ Si checksum OK → APROBADO
   ├─ Si anomalía detectada → RECHAZADO
   ├─ Si cambios no autorizados → RECHAZADO
   └─ Si reglas violadas → RECHAZADO

4. Acción si RECHAZADO
   ├─ Generar reporte de rechazo
   ├─ Enviar alert a admin
   ├─ Registrar en audit trail
   ├─ Bloquear generación de reporte
   └─ Requerir investigación manual

5. Acción si APROBADO
   ├─ Generar reporte final
   ├─ Almacenar con checksum
   ├─ Registrar en checksums table
   ├─ Enviar a stakeholders
   └─ Archivar para auditoría
```

### 10. Referencias

- DynamoDB: https://docs.aws.amazon.com/dynamodb/
- Lambda: https://docs.aws.amazon.com/lambda/
- EventBridge: https://docs.aws.amazon.com/eventbridge/
- Data Integrity: https://docs.aws.amazon.com/whitepapers/latest/data-integrity/
- Audit Logging: https://docs.aws.amazon.com/general/latest/gr/aws-audit-logging.html
