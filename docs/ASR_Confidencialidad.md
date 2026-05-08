# ASR: Confidencialidad
## Bloquear Acceso No Autorizado a Datos de Otra Empresa (100%)

### 1. Descripción

**Requisito de Negocio:**
> Yo como sistema, ante un intento de acceso no autorizado a datos de otra empresa (ataque de acceso indebido o escalamiento de privilegios), dado que el sistema maneja múltiples empresas, quiero bloquear el acceso y garantizar que no se exponga información de terceros en el 100% de los casos.

**Objetivo:**
Garantizar que un usuario autenticado NO puede acceder a datos de otra empresa bajo ninguna circunstancia. El sistema debe bloquear 100% de intentos de acceso indebido.

### 2. Componentes de Infraestructura

#### 2.1 AWS WAF (Web Application Firewall)
- **Rate Limiting**: 2000 requests/5 minutos por IP
- **SQL Injection Protection**: Managed Rule Set
- **Common Threats**: AWS Managed Rules
- **IP Blocking**: Lista de IPs maliciosas
- **OWASP Top 10**: Protección incluida

#### 2.2 VPC Isolation
- **VPC Flow Logs**: Todos los tráficos capturados
- **Security Groups**: Reglas restrictivas
  - Ingreso: Solo desde ALB (puerto 8000)
  - Egreso: HTTPS (443), DNS (53), DB (5432)
- **Network ACLs**: Validación adicional

#### 2.3 Encriptación

**En Tránsito:**
- TLS 1.2+ obligatorio para todas las conexiones
- ALB: HTTPS con certificado ACM
- Database: SSL requerido (rds.force_ssl = 1)

**En Reposo:**
- KMS Key para encriptación de datos
- RDS: Storage encrypted = true
- DynamoDB: Encryption enabled
- S3: Server-side encryption (SSE)

#### 2.4 IAM Roles y Políticas (Mínimo Privilegio)
```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "arn:aws:logs:region:account:log-group:/aws/project/*"
}
```

#### 2.5 Database Security
- Multi-AZ replication
- VPC subnet group (no público)
- Parameter Group: rds.force_ssl = 1
- Enhanced Monitoring habilitado

### 3. Flujo de Control de Acceso

```
┌──────────────────────────────────────┐
│ Usuario A (Empresa 1) intenta acceder │
│ a datos de Empresa 2                  │
└────────────────┬─────────────────────┘
                 │
                 ▼
    ┌────────────────────────┐
    │ WAF: Rate limiting OK?  │
    └────────┬───────────────┘
             │ SÍ
             ▼
    ┌────────────────────────┐
    │ WAF: SQL Injection?     │
    └────────┬───────────────┘
             │ NO
             ▼
    ┌────────────────────────────────┐
    │ ALB: Valida certificado SSL/TLS│
    └────────┬───────────────────────┘
             │ OK
             ▼
    ┌────────────────────────────────────┐
    │ Security Group: Autorizado origen?  │
    └────────┬───────────────────────────┘
             │ SÍ
             ▼
    ┌──────────────────────────────────────┐
    │ Aplicación: Verificar tenant_id      │
    │ (Usuario A != Empresa 2)             │
    └────────┬─────────────────────────────┘
             │ ACCESO DENEGADO
             ▼
    ┌──────────────────────────────────────┐
    │ Retornar 403 Forbidden               │
    │ Registrar intento en CloudWatch Logs │
    │ Disparar alarma de seguridad         │
    └──────────────────────────────────────┘
```

### 4. Pruebas Implementadas

#### 4.1 Configuración de WAF

**test_waf_enabled_on_alb**
- Verifica que WAF está vinculado al ALB
- Confirma que Web ACL existe
- Valida aplicación de reglas

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_waf_enabled_on_alb -v
```

**test_waf_rules_configured**
- Valida que WAF tiene al menos 3 reglas activas
- Confirma: Rate limiting, SQL injection, Common rules
- Verifica que todas están en estado activo

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_waf_rules_configured -v
```

#### 4.2 Configuración de Security

**test_security_groups_restrictive**
- Verifica que Security Group es restrictivo
- Confirma ingreso SOLO desde ALB
- Valida egreso limitado (HTTPS, DNS, DB)
- Asegura NO hay all-traffic (0.0.0.0/0)

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_security_groups_restrictive -v
```

**test_vpc_flow_logs_enabled**
- Confirma que VPC Flow Logs está habilitado
- Valida que todos los tráficos se registran
- Permite auditoría posterior de intentos maliciosos

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_vpc_flow_logs_enabled -v
```

#### 4.3 Encriptación y Protección de Datos

**test_rds_encryption_at_rest**
- Valida que RDS está encriptada en reposo
- Confirma KMS key configurada
- Verifica StorageEncrypted = true

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_rds_encryption_at_rest -v
```

**test_rds_ssl_requirement**
- Verifica parámetro rds.force_ssl = 1
- Asegura que SSL es obligatorio para conexiones
- Confirma que plain-text connections se rechazan

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_rds_ssl_requirement -v
```

**test_tls_version_on_alb**
- Valida que ALB usa TLS 1.2+
- Confirma SSL policy moderna (ELBSecurityPolicy-TLS-1-2-2017-01+)
- Asegura protección contra ataques de downgrade

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_tls_version_on_alb -v
```

#### 4.4 Detección de Intrusiones

**test_cloudwatch_alarms_for_unauthorized_access**
- Verifica que existe alarma para acceso no autorizado
- Confirma que alarma está activa
- Valida alertas se disparan en intentos

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentiality::test_cloudwatch_alarms_for_unauthorized_access -v
```

#### 4.5 Tests de Ataque

**test_waf_blocks_sql_injection_attempt**
- Intenta SQL injection
- Valida que WAF bloquea con 403
- Confirma protección de aplicación

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentialityAccess::test_waf_blocks_sql_injection_attempt -v
```

**test_rate_limiting_prevents_brute_force**
- Hace 20 requests rápidos
- Valida que después de threshold se retorna 429
- Confirma rate limiting previene fuerza bruta

```bash
pytest tests/confidentiality_tests/test_confidentiality.py::TestConfidentialityAccess::test_rate_limiting_prevents_brute_force -v
```

### 5. Matriz de Protección

```
┌──────────────────────────┬──────────────────────────────┐
│ Tipo de Ataque           │ Defensa                      │
├──────────────────────────┼──────────────────────────────┤
│ SQL Injection            │ WAF + Parameter Binding      │
│ Cross-Site Scripting     │ WAF + Django CSRF Protection │
│ CSRF                     │ Django Middleware            │
│ Brute Force / DDoS       │ Rate Limiting WAF            │
│ Man-in-the-Middle        │ TLS 1.2+ Obligatorio         │
│ Data Breach (reposo)     │ KMS Encryption               │
│ Escalamiento Privilegios │ IAM Mínimo Privilegio        │
│ Acceso Indebido Datos    │ Tenant Isolation (App)       │
│ VPC Breach               │ Security Groups + NACLs      │
│ Credential Theft         │ Encrypted Connections        │
└──────────────────────────┴──────────────────────────────┘
```

### 6. Métricas de Monitoreo

```
CloudWatch Dashboard: monitoring-app-confidentiality

Métricas principales:
┌──────────────────────────────────────────────────────┐
│ WAF Metrics (AWS/WAF)                                │
│ - Blocked Requests: # of malicious requests blocked │
│ - Allowed Requests: # of legitimate requests         │
│ - Rate: Should be 0 blocked in normal operation      │
│                                                      │
│ Security Alerts (Custom)                            │
│ - UnauthorizedAccessAttempts                        │
│ - FailedAuthenticationAttempts                      │
│ - SuspiciousDataAccessPatterns                      │
│                                                      │
│ Database Connections (AWS/RDS)                      │
│ - SSL Connection Count > Total Connections          │
│ - Failed SSL Connections == 0                       │
│                                                      │
│ VPC Flow Logs Analysis                              │
│ - Rejected Packets                                  │
│ - Denied Connections                                │
│ - Anomalous Traffic Patterns                        │
└──────────────────────────────────────────────────────┘
```

### 7. Alertas Configuradas

```
┌──────────────────────────────────────────────────────┐
│ Alarma: UnauthorizedAccessAttempts                  │
│ - Threshold: >= 5 intentos por 5 min                │
│ - Action: SNS alert a admin                         │
│ - Priority: HIGH                                    │
│                                                      │
│ Alarma: WafBlockedRequests                          │
│ - Threshold: Sudden spike in blocked requests       │
│ - Action: SNS alert + Auto-remediation              │
│ - Priority: CRITICAL if > 100 en 1 min             │
│                                                      │
│ Alarma: SSLConnectionFailure                        │
│ - Threshold: > 0 failed SSL connections             │
│ - Action: Investigate y alert                       │
│ - Priority: MEDIUM                                  │
│                                                      │
│ Alarma: VPCFlowLogDeniedConnections                 │
│ - Threshold: Anomalous increase                     │
│ - Action: Review and alert                          │
│ - Priority: MEDIUM                                  │
└──────────────────────────────────────────────────────┘
```

### 8. Checklist de Seguridad

```
Antes de ir a Producción:
☐ WAF está habilitado en ALB
☐ Todas las reglas WAF están activas
☐ Security Groups son restrictivos (no 0.0.0.0/0)
☐ RDS está encriptado (StorageEncrypted=true)
☐ RDS requiere SSL (rds.force_ssl=1)
☐ KMS Keys están configuradas correctamente
☐ VPC Flow Logs está habilitado por 90 días
☐ CloudWatch Alarms están activas
☐ SNS notifications están configuradas
☐ IAM roles siguen principio mínimo privilegio
☐ Certificado SSL es válido y actualizado
☐ Todos los tests de seguridad pasan
☐ Penetration testing completado
☐ Security audit passed
```

### 9. Procedimiento de Respuesta ante Incidente

```
Evento: Intento de acceso no autorizado detectado

1. Detección (automática en < 1 min)
   - CloudWatch alarm trigger
   - SNS alert enviada

2. Respuesta Inmediata (< 5 min)
   - Bloquear IP fuente (WAF IP set)
   - Habilitar logging detallado
   - Notificar a Security Team

3. Investigación (30-60 min)
   - Revisar VPC Flow Logs
   - Analizar WAF logs
   - Revisar CloudWatch Logs
   - Identificar patrón de ataque

4. Remediation (< 2 horas)
   - Aplicar reglas WAF adicionales si es necesario
   - Rotación de credenciales si aplica
   - Verificar que datos no fueron expuestos

5. Post-Incident (24 horas)
   - Generar reporte de seguridad
   - Actualizar procedures
   - Comunicar a stakeholders
```

### 10. Referencias

- AWS WAF: https://docs.aws.amazon.com/waf/
- VPC Security: https://docs.aws.amazon.com/vpc/
- RDS Security: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.html
- KMS: https://docs.aws.amazon.com/kms/
- Multi-tenancy: https://aws.amazon.com/es/blogs/security/multi-tenant-architecture-strategies/
