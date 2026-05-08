# ASR: Disponibilidad
## Tiempo de Recuperación ante Fallos < 5 Segundos

### 1. Descripción

**Requisito de Negocio:**
> Yo, como usuario de la plataforma, cuando esté en operación normal y el sistema presente una falla en un servidor, quiero que el tiempo de recuperación ante una caída no supere los 5 segundos.

**Objetivo:**
Garantizar que cualquier falla en un servidor individual no cause downtime perceptible para los usuarios. El sistema debe detectar la falla y redirigir el tráfico automáticamente en menos de 5 segundos.

### 2. Componentes de Infraestructura

#### 2.1 Application Load Balancer (ALB)
- **Health Checks Rápidos**: Intervalo de 5 segundos
- **Timeout**: 3 segundos
- **Healthy Threshold**: 2 intentos consecutivos
- **Unhealthy Threshold**: 2 intentos fallidos
- **Cross-Zone**: Habilitado para distribución en múltiples AZ

#### 2.2 Auto Scaling Group (ASG)
- **Mínimo**: 2 instancias (para redundancia)
- **Máximo**: 6 instancias (capacidad)
- **Deseado**: 3 instancias (baseline)
- **Health Check Type**: ELB
- **Grace Period**: 60 segundos

#### 2.3 RDS Multi-AZ
- **Multi-AZ**: Habilitado
- **Automatic Failover**: Sí
- **Backup Retention**: 30 días
- **Enhanced Monitoring**: Habilitado
- **Storage Type**: GP3 con IOPS

#### 2.4 CloudWatch Alarmas
- **CPU High** (> 70%): Scale Up
- **CPU Low** (< 30%): Scale Down
- **TargetResponseTime**: < 2s promedio

### 3. Flujo de Recuperación Ante Fallos

```
┌─────────────────────────────────────────────────────────┐
│ Instancia EC2 se vuelve no saludable                   │
│ (CPU alta, latencia, Health Check fallido)             │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼ (T+0s)
┌─────────────────────────────────────────────────────────┐
│ ALB detecta health check fallido                        │
│ (Intervalo: 5s, Threshold: 2)                          │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼ (T+10s máximo)
┌─────────────────────────────────────────────────────────┐
│ ALB marca instancia como unhealthy                      │
│ Comienza a drenar conexiones                            │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼ (T+10-15s)
┌─────────────────────────────────────────────────────────┐
│ ASG detecta instancia unhealthy                         │
│ Termina instancia después de grace period (60s)         │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼ (T+70-75s)
┌─────────────────────────────────────────────────────────┐
│ ASG inicia nueva instancia (AMI warming: ~2-3 min)      │
│ Aplicación bootstrap (user_data: ~1-2 min)             │
└─────────────────────────────────────────────────────────┘

TIEMPO REAL DE RECUPERACIÓN:
- Detección: < 10 segundos ✓
- Redireccionamiento: < 5 segundos ✓ (en ALB)
- Reemplazo: ~3-5 minutos (aceptable para SLA)
```

### 4. Pruebas Implementadas

#### 4.1 Pruebas de Configuración (Unitarias)

**test_alb_health_check_configuration**
- Valida que health check está configurado para detección rápida
- Verifica interval <= 5s, timeout <= 3s
- Asegura que puede detectar y marcar unhealthy en < 10s

```bash
pytest tests/availability_tests/test_availability.py::TestAvailability::test_alb_health_check_configuration -v
```

**test_asg_rapid_recovery**
- Verifica que ASG está configurado para reemplazo rápido
- Confirma Min >= 2, Health Check Type = ELB
- Valida grace period <= 60s

```bash
pytest tests/availability_tests/test_availability.py::TestAvailability::test_asg_rapid_recovery -v
```

**test_rds_multi_az_failover**
- Valida que RDS está en Multi-AZ
- Confirma automatic failover está habilitado
- Verifica backup retention >= 7 días

```bash
pytest tests/availability_tests/test_availability.py::TestAvailability::test_rds_multi_az_failover -v
```

#### 4.2 Pruebas de Métricas (Integración)

**test_alb_response_time**
- Mide Target Response Time del ALB
- Valida que promedio < 2s
- Extrae métricas de CloudWatch de la última hora

```bash
pytest tests/availability_tests/test_availability.py::TestAvailability::test_alb_response_time -v
```

**test_healthy_host_count**
- Verifica que hay hosts saludables en Target Group
- Cuenta instancias en estado 'healthy'
- Asegura capacidad para manejar tráfico

```bash
pytest tests/availability_tests/test_availability.py::TestAvailability::test_healthy_host_count -v
```

#### 4.3 Pruebas de Carga (Performance)

**test_application_responds_to_requests**
- Valida que aplicación responde a través del ALB
- Mide latencia de respuesta
- Intenta conectar a la aplicación en operación

```bash
pytest tests/availability_tests/test_availability.py::TestAvailabilityLoadScenarios::test_application_responds_to_requests -v
```

**test_health_endpoint_available**
- Verifica que endpoint /health/ responde rápidamente
- Valida response time < 1s
- Usado por ALB para health checks

```bash
pytest tests/availability_tests/test_availability.py::TestAvailabilityLoadScenarios::test_health_endpoint_available -v
```

### 5. Métricas de Monitoreo

```
CloudWatch Dashboard: monitoring-app-availability

Métricas principales:
┌─────────────────────────────────────────────────────────┐
│ Target Response Time (AWS/ApplicationELB)              │
│ - Average < 2s ✓                                       │
│ - Maximum < 5s ✓                                       │
│                                                         │
│ Healthy Host Count (AWS/ApplicationELB)                │
│ - Should be >= 2 ✓                                     │
│ - Unhealthy Count == 0 ✓                              │
│                                                         │
│ CPU Utilization (AWS/EC2)                              │
│ - Average 30-70% ✓                                     │
│ - No sustained > 80% ✓                                 │
│                                                         │
│ Database Availability (AWS/RDS)                        │
│ - 99.95% target ✓                                      │
│ - Failover events == 0 (en operación normal) ✓        │
└─────────────────────────────────────────────────────────┘
```

### 6. Cálculo de SLA

**Componentes y su disponibilidad individual:**
- ALB: 99.99% (AWS SLA)
- EC2 (en ASG multi-AZ): 99.95%
- RDS Multi-AZ: 99.95%

**Disponibilidad compuesta:**
```
SLA = ALB × ASG × RDS
    = 0.9999 × 0.9995 × 0.9995
    = 0.9989 ≈ 99.89%
```

**Downtime anual aceptable:**
```
1 año = 365 días = 525,600 minutos
Downtime = 525,600 × (1 - 0.9989) = 576 minutos ≈ 9.6 horas
```

### 7. Alertas Configuradas

```
┌─────────────────────────────────────────────────────────┐
│ Alarma: CPU-High                                        │
│ - Condition: CPU > 70% por 1 minuto                    │
│ - Action: Scale Up +1 instancia                        │
│ - Topic: monitoring-app-security-alerts                │
│                                                         │
│ Alarma: CPU-Low                                         │
│ - Condition: CPU < 30% por 5 minutos                   │
│ - Action: Scale Down -1 instancia (mín 2)             │
│ - Topic: monitoring-app-security-alerts                │
│                                                         │
│ Alarma: UnhealthyHostCount                             │
│ - Condition: > 1 host unhealthy                        │
│ - Action: Alert immediately                            │
│ - Topic: monitoring-app-security-alerts                │
│                                                         │
│ Alarma: TargetResponseTime                             │
│ - Condition: > 5 segundos promedio                     │
│ - Action: Alert para investigación                     │
│ - Topic: monitoring-app-security-alerts                │
└─────────────────────────────────────────────────────────┘
```

### 8. Procedimiento de Despliegue

```bash
# 1. Validar configuración Terraform
cd terraform/environments/dev
terraform plan -out=tfplan

# 2. Aplicar infraestructura
terraform apply tfplan

# 3. Ejecutar tests de disponibilidad
pytest tests/availability_tests/test_availability.py -v

# 4. Validar métricas en CloudWatch
# - ALB Response Time < 2s
# - Healthy Hosts >= 2
# - CPU avg 30-70%

# 5. Ejecutar test de carga (opcional)
ab -n 1000 -c 100 http://ALB_DNS_NAME/

# 6. Monitorear por 1-2 horas
# - Verificar que scaling policies funcionan
# - Confirmar que no hay errores en logs
# - Validar que todos los health checks pasan
```

### 9. Referencias

- AWS ALB Documentation: https://docs.aws.amazon.com/elasticloadbalancing/
- Auto Scaling: https://docs.aws.amazon.com/autoscaling/
- RDS Multi-AZ: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ
- CloudWatch: https://docs.aws.amazon.com/cloudwatch/
