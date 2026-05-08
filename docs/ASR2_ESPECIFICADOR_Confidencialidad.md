# ASR 2: Confidencialidad (Aislamiento Multi-tenant)
## Prueba de aislamiento de datos entre empresas clientes

### ASR Involucrado
**Yo, como sistema, ante un intento de acceso no autorizado a datos de otra empresa (ataque de acceso indebido o escalamiento de privilegios), dado que el sistema maneja múltiples empresas, quiero bloquear el acceso y garantizar que no se exponga información de terceros en el 100% de los casos.**

### Propósito del Experimento
Evaluar si la arquitectura con ProxySQL y esquemas separados por tenant es capaz de aislar los datos de cada empresa cliente, impidiendo que un usuario de una empresa acceda a información de otra.

### Resultados Esperados
Se espera que, ante un intento de acceso malicioso desde un usuario autenticado en la Empresa A hacia datos de la Empresa B, el sistema bloquee la petición y **no exponga información de la Empresa B en el 100% de los casos**.

### Infraestructura Computacional Requerida

| Componente | Especificación | Cantidad | Detalle |
|-----------|----------------|---------| --------|
| **API Gateway + Auth** | Auth0 o API Gateway AWS | 1 | Autenticación y tenant identification |
| **Balanceador de Carga** | AWS Application Load Balancer | 1 | Enrutamiento HTTP/HTTPS |
| **EC2 - Servidor de Usuarios** | t3.medium Ubuntu 22.04 | 1 | Django + lógica de negocio |
| **EC2 - Servidor de Datos** | t3.medium Ubuntu 22.04 | 1 | Django + lógica de negocio |
| **ProxySQL** | EC2 t3.small + ProxySQL | 1 | Enrutador de queries por tenant |
| **Base de Datos** | AWS RDS PostgreSQL 15.3 | 1 | Esquemas: empresa_a, empresa_b, empresa_c |
| **VPC + Security Groups** | AWS VPC | 1 | Aislamiento de red |
| **Computador Personal** | Python requests + Burp Suite | - | Simulación de ataques |

### Configuración de Esquemas y Tenants

```sql
-- RDS PostgreSQL estructura:
CREATE SCHEMA empresa_a;
CREATE SCHEMA empresa_b;
CREATE SCHEMA empresa_c;

-- Tablas por schema (ejemplo):
-- empresa_a.usuarios, empresa_a.costos, empresa_a.reportes
-- empresa_b.usuarios, empresa_b.costos, empresa_b.reportes
-- empresa_c.usuarios, empresa_c.costos, empresa_c.reportes

-- ProxySQL enrutamiento:
-- Usuario autenticado como empresa_a → ProxySQL enruta a empresa_a.*
-- Usuario autenticado como empresa_b → ProxySQL enruta a empresa_b.*
-- Intentar acceder a otro schema → ProxySQL rechaza (PERMISSION DENIED)
```

### Configuración de ProxySQL

```yaml
ProxySQL Configuration:
  Rewrite Rules:
    - Pattern: SELECT .* FROM (.*)
      Where: IF tenant != extracted_schema THEN DENY
    - Pattern: INSERT/UPDATE/DELETE
      Where: IF tenant != target_schema THEN DENY
  
  Hostgroups:
    - empresa_a_group: read/write to empresa_a schema
    - empresa_b_group: read/write to empresa_b schema
    - empresa_c_group: read/write to empresa_c schema
  
  Query Rules:
    - User: usuario_a@empresa_a → Hostgroup: empresa_a_group
    - User: usuario_b@empresa_b → Hostgroup: empresa_b_group
    - User: usuario_c@empresa_c → Hostgroup: empresa_c_group
    - Any other tenant access attempt → DENY with LOG
```

### Descripción del Experimento

#### Fase 1: Setup
1. Desplegar ProxySQL en EC2 separada
2. Crear 3 esquemas en RDS (empresa_a, empresa_b, empresa_c)
3. Crear usuarios en ProxySQL mapeos (usuario_a → empresa_a, etc.)
4. Autenticar usuarios en API Gateway:
   - **Usuario_A**: tenant_id = empresa_a, email: usuario_a@empresa_a.com
   - **Usuario_B**: tenant_id = empresa_b, email: usuario_b@empresa_b.com

#### Fase 2: Validación Baseline
- Usuario_A realiza query a empresa_a.usuarios → **OK (debe permitir)**
- Usuario_B realiza query a empresa_b.usuarios → **OK (debe permitir)**

#### Fase 3: Simulación de Ataques (100% de casos)

**Ataque 1: Modificación de tenant en HTTP header**
```
GET /api/usuarios
Headers: 
  - Authorization: Bearer <token_usuario_a>
  - X-Tenant: empresa_b  ← Intenta override

Esperado: DENY con error 403 Forbidden
Resultado: ProxySQL valida contra token, ignorar header → PASS
```

**Ataque 2: Inyección SQL**
```
GET /api/usuarios?name='; SELECT * FROM empresa_b.usuarios; --

Esperado: DENY con error SQL injection blocked
Resultado: ProxySQL/WAF detecta y bloquea → PASS
```

**Ataque 3: Escalamiento de Privilegios**
```
POST /api/admin/users
Headers: 
  - Authorization: Bearer <token_usuario_a>
Body:
  {
    "role": "admin",
    "tenant": "empresa_b"
  }

Esperado: DENY con error 403 Forbidden (usuario_a no tiene privilegios en empresa_b)
Resultado: API Gateway + ProxySQL validan tenant → PASS
```

**Ataque 4: Conexión Directa a RDS (bypass ProxySQL)**
```
Intentar conexión: psql -h rds-endpoint -U usuario_a -d empresa_b

Esperado: DENY (conexión rechazada)
Resultado: Security Group bloquea; usuario_a credenciales no válidas para empresa_b → PASS
```

**Ataque 5: Modificación de datos de otro tenant**
```
UPDATE empresa_b.costos SET amount = 0 WHERE id = 1

Esperado: DENY con error (usuario_a no tiene permisos en empresa_b)
Resultado: ProxySQL + RDS roles validan → PASS
```

### Criterios de Éxito

✅ **PASS si:**
- 100% de intentos de acceso a datos de otro tenant son bloqueados
- 100% de ataques de SQL injection son mitigados
- 100% de intentos de escalamiento de privilegios son rechazados
- Cero exposición de datos de terceros en respuestas HTTP
- Todos los incidentes quedan registrados en audit logs

❌ **FAIL si:**
- Algún intento de acceso a otro tenant tiene éxito
- Datos de empresa_b son visibles para usuario_a
- Inyección SQL ejecuta queries en otro schema
- Error 500 que expone stack trace con datos sensibles

### Monitoreo y Observabilidad

```
ProxySQL Metrics:
- query_rules_matched (por tenant)
- access_denied_count (por tenant)
- permission_error_count

CloudWatch Logs:
- ProxySQL errors: access denied
- Application errors: unauthorized tenant access
- API Gateway: 403 Forbidden responses

CloudWatch Alarms:
- ProxySQL permission errors > 0 → ALERT
- SQL injection attempt detected → CRITICAL
- Unauthorized tenant access attempt → CRITICAL
```

### Auditoría y Registro

```sql
-- Tabla de auditoría en RDS (shared audit schema):
CREATE SCHEMA audit;
CREATE TABLE audit.access_log (
  id SERIAL PRIMARY KEY,
  timestamp TIMESTAMP DEFAULT NOW(),
  user_id VARCHAR(100),
  tenant_id VARCHAR(100),
  action VARCHAR(50),
  target_tenant VARCHAR(100),
  result ENUM('ALLOWED', 'DENIED'),
  reason VARCHAR(500)
);

-- ProxySQL logs todos los intentos de acceso:
SELECT * FROM audit.access_log WHERE result = 'DENIED';
```

### Recuperación Post-Experimento

1. Revisar audit logs para validar registro de todos los intentos
2. Verificar que permisos de usuarios siguen intactos
3. Confirmar que datos de cada tenant están íntegros
4. Limpiar logs de prueba

### Notas Técnicas

- ProxySQL debe estar en security group separada, con acceso restringido desde App Servers
- RDS debe bloquear conexiones directas (solo desde ProxySQL)
- API Gateway valida tenant en cada request (antes de llegar a App Server)
- Audit table debe estar en schema separado (no accesible por usuarios normales)
- Considerar rate limiting de 403 errors (indicativo de ataque)
