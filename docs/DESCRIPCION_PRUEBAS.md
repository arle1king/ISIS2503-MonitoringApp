<!-- 
DESCRIPCIÓN DE PRUEBAS PARA CADA ASR
Documento que detalla cada prueba, su propósito y cómo validar los requisitos
-->

# Descripción Detallada de Pruebas

## 🟢 ASR 1: DISPONIBILIDAD - Recuperación < 5 segundos

### Prueba 1: test_alb_health_check_configuration
**Propósito:** Validar que el ALB tiene health checks configurados para detección rápida

**Validaciones:**
- ✓ Interval <= 5 segundos (ALB chequea cada 5s)
- ✓ Timeout <= 3 segundos (debe responder rápido)
- ✓ Healthy Threshold <= 2 (máximo 2 chequeos OK para pasar)
- ✓ Unhealthy Threshold <= 2 (máximo 2 fallos para marcar como no saludable)

**Por qué es importante:**
Detecta instancias defectuosas rápidamente. Si tarda 30 segundos, los usuarios ven error. Con 5 segundos, casi invisible.

**Cálculo de tiempo detección:**
```
Peor caso: 2 fallos × 5 seg/intento = 10 segundos
Dentro de objetivo < 5 seg de recovery ✓
```

---

### Prueba 2: test_asg_rapid_recovery
**Propósito:** Validar que Auto Scaling Group reemplaza instancias muertas rápidamente

**Validaciones:**
- ✓ Min Size >= 2 (redundancia: si una falla, otra carga)
- ✓ Max Size >= 4 (capacidad suficiente para picos)
- ✓ Health Check Type = ELB (usa ALB para detectar)
- ✓ Grace Period <= 60 seg (espera razonable para booteo)

**Por qué es importante:**
Si una instancia muere, el ASG detecta y reemplaza automáticamente. Sin ASG = downtime manual.

**Flujo:**
```
Instancia muere → ALB la marca unhealthy → ASG detecta → Inicia nueva → En 3-5 minutos lista
```

---

### Prueba 3: test_rds_multi_az_failover
**Propósito:** Validar que base de datos tiene redundancia geográfica

**Validaciones:**
- ✓ Multi AZ = true (standby en otra zona)
- ✓ Automatic Failover enabled (no requiere intervención)
- ✓ Backup Retention >= 7 días (pueda recuperarse datos)

**Por qué es importante:**
Si datacenter A falla, datacenter B toma el relevo automáticamente. Sin Multi-AZ = database down.

**RTO (Recovery Time Objective):** < 2 minutos típicamente

---

### Prueba 4: test_alb_response_time
**Propósito:** Validar que ALB responde en tiempo aceptable

**Validaciones:**
- ✓ Average Response Time < 2 segundos
- ✓ Maximum Response Time < 5 segundos

**Por qué es importante:**
Usuario no debe percibir latencia. Si ALB tarda 10 segundos, eso es downtime.

**Métrica obtenida de:** CloudWatch AWS/ApplicationELB → TargetResponseTime

---

### Prueba 5: test_healthy_host_count
**Propósito:** Validar que hay suficientes instancias saludables

**Validaciones:**
- ✓ Healthy Hosts >= 1 (hay al menos una disponible)
- ✓ Preferiblemente >= 2 (para redundancia)

**Por qué es importante:**
Si 0 hosts saludables = error 503 Service Unavailable.

**En el dashboard:**
```
Target Group State: healthy/total
Ejemplo: 2 healthy / 3 total → OK (1 se está reparando)
         0 healthy / 3 total → CRÍTICO (downtime)
```

---

### Prueba 6: test_application_responds_to_requests
**Propósito:** Validar que aplicación Django responde a través del ALB

**Validaciones:**
- ✓ Status Code = 200 OK
- ✓ Response time < 10 segundos

**Por qué es importante:**
Prueba end-to-end que todo el stack funciona.

**Flujo:**
```
Client → Internet → ALB (Cloud) → Security Group → EC2 → Django app → Response
```

---

### Prueba 7: test_health_endpoint_available
**Propósito:** Validar que endpoint /health/ responde rápidamente

**Validaciones:**
- ✓ Status = 200
- ✓ Response time < 1 segundo
- ✓ JSON response valido

**Por qué es importante:**
Este es el endpoint que ALB usa para health checks. Si lento, ALB cree que está muerta.

**Django setup requerido:**
```python
# monitoring/views.py
def health(request):
    return JsonResponse({"status": "healthy"}, status=200)

# monitoring/urls.py
path('health/', health),
```

---

### Prueba 8: test_cloudwatch_alarms_scaling_policies
**Propósito:** Validar que existen alarmas para escalar automáticamente

**Validaciones:**
- ✓ Alarma "CPU-High": CPU > 70% → Scale Up
- ✓ Alarma "CPU-Low": CPU < 30% → Scale Down

**Por qué es importante:**
Si demanda aumenta, agregar instancias. Si baja, remover. Automático = dinero y performance.

**Escenarios:**
```
Black Friday (alto tráfico):
  CPU sube → 75% → Alarma dispara → ASG agrega 2 instancias → CPU baja a 60%

Madrugada (bajo tráfico):
  CPU baja → 25% → Alarma dispara → ASG quita 1 instancia → Ahorra dinero
```

---

### Prueba 9: test_database_availability_metric
**Propósito:** Validar disponibilidad de la base de datos

**Validaciones:**
- ✓ Database Availability > 99.9%
- ✓ Idealmente > 99.95% (multi-AZ)

**Por qué es importante:**
Si database offline, aplicación cae. Multi-AZ asegura que siempre hay una.

---

### Prueba 10: test_failover_detection_time
**Propósito:** (Test intrusivo) Medir tiempo real de detección de falla

**Validaciones:**
- ✓ Instancia se marca unhealthy en < 10 segundos
- ✓ Tráfico se redirige en < 5 segundos

**Por qué es importante:**
VALIDACIÓN REAL del ASR. Simula una falla verdadera.

**Nota:** Test es "intrusivo" porque causa downtime real. Solo ejecutar en environment de testing.

---

---

## 🔴 ASR 2: CONFIDENCIALIDAD - Bloquear acceso no autorizado (100%)

### Prueba 1: test_waf_enabled_on_alb
**Propósito:** Verificar que AWS WAF está activo y vinculado

**Validaciones:**
- ✓ WAF existe
- ✓ WAF está vinculado a ALB
- ✓ WAF tiene Web ACL configurada

**Por qué es importante:**
WAF es la primera línea de defensa. Si no existe = acceso a ataques simples (SQL injection, XSS, DDoS).

**Analogía:** WAF = guardia de seguridad en la entrada

---

### Prueba 2: test_waf_rules_configured
**Propósito:** Validar que WAF tiene reglas de protección activas

**Validaciones:**
- ✓ Regla: Block IPs (lista de IPs maliciosas)
- ✓ Regla: Common Rule Set (OWASP Top 10)
- ✓ Regla: SQL Injection Rules
- ✓ Regla: Rate Limiting (máximo 2000 req/5min)

**Por qué es importante:**
Reglas = políticas de defensa. Sin reglas = WAF inútil.

**Ejemplos bloqueados:**
```
SQL Injection: ' OR '1'='1
XSS: <script>alert('hi')</script>
DDoS: 5000 requests en 10 segundos → Bloqueado
Malicious IP: 203.0.113.1 → Bloqueado
```

---

### Prueba 3: test_security_groups_restrictive
**Propósito:** Validar que Security Groups usan principio de mínimo privilegio

**Validaciones:**
- ✓ Ingreso SOLO desde ALB (puerto 8000)
- ✓ NO ingreso desde 0.0.0.0/0 (internet abierto)
- ✓ Egreso limitado: HTTPS (443), DNS (53), DB (5432)
- ✓ NO egreso a 0.0.0.0/0 (all traffic)

**Por qué es importante:**
Si aplicación acepta conexiones de internet = acceso directo = bypass WAF.

**Analogía:** Security Groups = zona de acceso restringido (necesitas pasar ALB primero)

---

### Prueba 4: test_rds_encryption_at_rest
**Propósito:** Validar que datos en BD están encriptados

**Validaciones:**
- ✓ StorageEncrypted = true
- ✓ KMS Key configurada (especificar cuál)

**Por qué es importante:**
Si alguien roba el disco duro de RDS = datos sin protección sin encriptación. Con encriptación = basura.

**Analogy:** Encryption = caja fuerte. Disco = llave adentro

---

### Prueba 5: test_rds_ssl_requirement
**Propósito:** Validar que conexiones a BD usan SSL/TLS

**Validaciones:**
- ✓ Parámetro rds.force_ssl = 1
- ✓ Plain-text connections se rechazan

**Por qué es importante:**
Si conexión sin SSL = hacker entre aplicación y DB puede sniffear contraseñas.

---

### Prueba 6: test_tls_version_on_alb
**Propósito:** Validar que ALB usa TLS moderno (1.2+)

**Validaciones:**
- ✓ SSL Policy >= ELBSecurityPolicy-TLS-1-2-2017-01
- ✓ NO SSL 3.0 ni TLS 1.0 (vulnerables)

**Por qué es importante:**
TLS viejo = hacker puede desencriptar conexiones. TLS 1.2+ = seguro.

---

### Prueba 7: test_vpc_flow_logs_enabled
**Propósito:** Validar que se registra todo el tráfico para auditoría

**Validaciones:**
- ✓ VPC Flow Logs habilitado
- ✓ Retención >= 7 días
- ✓ Logs en CloudWatch

**Por qué es importante:**
Cuando alguien ataca, necesitas evidencia. Flow Logs = registro de todo.

**Caso de uso:**
```
Intento de ataque detectado:
1. Revisar Flow Logs
2. Ver patrón: IP 203.0.113.1 intentó acceso a puerto 5432
3. Bloquear IP en WAF
4. Reportar a seguridad
```

---

### Prueba 8: test_cloudwatch_alarms_for_unauthorized_access
**Propósito:** Validar que hay alertas para detectar acceso no autorizado

**Validaciones:**
- ✓ Alarma existe: "UnauthorizedAccessAttempts"
- ✓ Threshold = trigger en >= 5 intentos/5min
- ✓ Acción = enviar alert a SNS

**Por qué es importante:**
Detección automática = respuesta rápida. Si humano tiene que revisar logs = muy lento.

---

### Prueba 9: test_waf_blocks_sql_injection_attempt
**Propósito:** (Test práctico) Intentar SQL injection y validar que WAF lo bloquea

**Validaciones:**
- ✓ Payloads maliciosos retornan 403 Forbidden
- ✓ WAF bloquea antes que aplicación

**Por qué es importante:**
Prueba real que WAF funciona.

**Ejemplo:**
```
GET /search/?q=' OR '1'='1
WAF: BLOQUEADO ✓ (403 Forbidden)
```

---

### Prueba 10: test_rate_limiting_prevents_brute_force
**Propósito:** (Test práctico) Validar que rate limiting previene fuerza bruta

**Validaciones:**
- ✓ 20 requests rápidos en 1 segundo
- ✓ Después de ~10 requests → HTTP 429 (Too Many Requests)

**Por qué es importante:**
Ataque de fuerza bruta (probar 10,000 contraseñas/segundo) se bloquea.

---

---

## 🟡 ASR 3: INTEGRIDAD - Detectar datos modificados (100%)

### Prueba 1: test_dynamodb_audit_trail_exists
**Propósito:** Verificar que existe tabla de auditoría

**Validaciones:**
- ✓ Tabla "monitoring-app-audit-trail" existe
- ✓ PITR (Point-in-time recovery) habilitado
- ✓ Encriptación KMS activa

**Por qué es importante:**
Tabla de auditoría = registro inmutable de TODO lo que pasó. Si no existe = no hay prueba de modificaciones.

---

### Prueba 2: test_dynamodb_checksum_table_exists
**Propósito:** Verificar que existe tabla de checksums para reportes

**Validaciones:**
- ✓ Tabla "monitoring-app-report-checksums" existe
- ✓ Encriptación habilitada

**Por qué es importante:**
Checksums = fingerprint de los datos. Si datos cambian = checksum diferente = cambio detectado.

---

### Prueba 3: test_lambda_validation_function_exists
**Propósito:** Verificar que existe función Lambda para validar integridad

**Validaciones:**
- ✓ Lambda existe: "monitoring-app-data-validation"
- ✓ Runtime: Python 3.11
- ✓ Timeout: >= 60 segundos

**Por qué es importante:**
Lambda ejecuta validaciones cada 5 minutos. Sin Lambda = sin validación automática.

---

### Prueba 4: test_eventbridge_rules_for_integrity_checks
**Propósito:** Verificar que hay reglas que disparan validaciones

**Validaciones:**
- ✓ EventBridge Rule existe: "monitoring-app-integrity-check"
- ✓ Schedule: rate(5 minutes)
- ✓ Target: Lambda data_validation
- ✓ Status: ENABLED

**Por qué es importante:**
EventBridge = orquestador. Dispara Lambda cada 5 minutos sin intervención humana.

---

### Prueba 5: test_cloudwatch_metric_for_data_modification
**Propósito:** Verificar que hay alarma para detectar modificaciones

**Validaciones:**
- ✓ Métrica: "UnauthorizedDataModification"
- ✓ Alarma: threshold >= 1 (alerta en cualquier modificación sospechosa)

**Por qué es importante:**
Alertas = notificación inmediata si algo está mal.

---

### Prueba 6: test_checksum_generation
**Propósito:** (Test funcional) Validar que checksums detectan cambios

**Validaciones:**
```
1. Generar checksum de datos originales → "abc123..."
2. Generar checksum nuevamente → "abc123..." (idéntico)
3. Modificar datos (cambiar 1 centavo)
4. Generar checksum nuevamente → "xyz789..." (diferente)
5. Conclusión: Cambio detectado ✓
```

**Por qué es importante:**
Prueba el mecanismo de detección de cambios.

---

### Prueba 7: test_audit_trail_entry_structure
**Propósito:** Validar que entradas de auditoría tienen estructura correcta

**Validaciones:**
```
Campos requeridos:
- EntityId: Qué se modificó (ej: "RPT-2024-01")
- Timestamp: Cuándo (Unix timestamp)
- Action: Qué se hizo (CREATE, UPDATE, DELETE)
- Actor: Quién lo hizo (usuario o sistema)
- OldValue: Valor antes
- NewValue: Valor después
- Checksum: SHA-256 de los datos
- Status: APPROVED, REJECTED, PENDING
```

**Por qué es importante:**
Estructura consistente = fácil de analizar y auditar.

---

### Prueba 8: test_reject_modified_report_data
**Propósito:** (Test funcional) Validar que reportes modificados se rechazan

**Validaciones:**
```
Reporte Original:
{
  "EC2": 500.25,
  "RDS": 300.00,
  "S3": 700.25,
  "TOTAL": 1500.50
}
Checksum: "abc123..."

Intento de Modificación:
{
  "EC2": 500.25,
  "RDS": 300.00,
  "S3": 700.25,
  "TOTAL": 5000.00  ← Cambio fraudulento
}
Checksum: "xyz789..."

Validación: checksums NO coinciden → RECHAZADO ✓
```

**Por qué es importante:**
Demuestra que intentos de fraude (cambiar total de costos) se detectan.

---

### Prueba 9: test_audit_log_immutability
**Propósito:** Validar que registros de auditoría no pueden ser modificados

**Validaciones:**
- ✓ DynamoDB PITR habilitado
- ✓ Historial de cambios preservado
- ✓ Cambios anteriores no pueden ser editados

**Por qué es importante:**
Si hacker modifica audit trail = no hay prueba del crimen. Con PITR = imposible.

---

### Prueba 10: test_pre_report_generation_validation
**Propósito:** Validar flujo completo de validación antes de generar reporte

**Validaciones:**
```
Paso 1: Obtener datos del período
  Status: SUCCESS ✓
  
Paso 2: Generar checksum SHA-256
  Status: SUCCESS ✓
  
Paso 3: Comparar con checksum anterior
  Status: SUCCESS ✓
  Match: true ✓
  
Paso 4: Validar autorización
  Status: SUCCESS ✓
  Authorized: true ✓
  
Paso 5: Generar reporte
  Status: SUCCESS ✓
  Report ID: RPT-2024-01-001
  
Resultado Final: TODO OK → REPORTE GENERADO ✓
```

Si algún paso falla:
```
Paso 3: Comparar con checksum anterior
  Status: SUCCESS ✓
  Match: FALSE ✗ (Datos cambiaron)
  
Resultado Final: DATOS MODIFICADOS → REPORTE RECHAZADO ✗
```

**Por qué es importante:**
Prueba que el sistema RECHAZA reportes con datos comprometidos.

---

---

## 📊 Resumen de Pruebas

| ASR | Nombre | Total | Tipo |
|-----|--------|-------|------|
| **Disponibilidad** | test_availability.py | 10 | Config + Integration |
| **Confidencialidad** | test_confidentiality.py | 10 | Config + Security |
| **Integridad** | test_integrity.py | 10 | Validation + Functional |

**Total: 30+ pruebas**

---

## 🚀 Cómo Ejecutar

```bash
# Todas las pruebas
pytest tests/ -v

# Por ASR
pytest tests/availability_tests/ -v
pytest tests/confidentiality_tests/ -v
pytest tests/integrity_tests/ -v

# Prueba específica
pytest tests/availability_tests/test_availability.py::TestAvailability::test_alb_health_check_configuration -v
```

---

## ✅ Criterios de Aceptación

Para que un ASR se considere "implementado":
- ✓ Todos los tests pasan
- ✓ Configuración validada en AWS Console
- ✓ Métricas en CloudWatch muestran valores correctos
- ✓ Alarmas funcionan (se pueden probar manualmente)
- ✓ Documentación completa

