# ASR 1: Disponibilidad (Failover)
## Prueba de recuperación automática ante fallo de servidor

### ASR Involucrado
**Yo, como usuario de la plataforma, cuando esté en operación normal y el sistema presente una falla en un servidor, quiero que el tiempo de recuperación ante una caída no supere los 5 segundos.**

### Propósito del Experimento
Evaluar si la arquitectura con balanceador de carga y múltiples instancias es capaz de detectar la caída de un servidor y redirigir el tráfico a un nodo saludable en menos de 5 segundos, sin afectar la experiencia del usuario.

### Resultados Esperados
Se espera que, ante la falla de una instancia EC2, el balanceador de carga detecte la caída mediante health checks y redirija todo el tráfico a las instancias restantes en un tiempo menor o igual a 5 segundos, **sin pérdida de peticiones activas**.

### Infraestructura Computacional Requerida

| Componente | Especificación | Cantidad | Detalle |
|-----------|----------------|---------| --------|
| **Balanceador de Carga** | AWS Application Load Balancer | 1 | Cross-zone enabled, HTTP/HTTPS |
| **EC2 - Servidor de Usuarios** | t3.medium Ubuntu 22.04 | 1 | Python + Django (puerto 8000) |
| **EC2 - Servidor de Datos** | t3.medium Ubuntu 22.04 | 1 | Python + Django (puerto 8000) |
| **EC2 - Servidor de Notificaciones** | t3.medium Ubuntu 22.04 | 1 | Python + Django (puerto 8000) |
| **Auto Scaling Group** | ASG | 1 | Min: 3, Max: 6, Desired: 3 |
| **Base de Datos** | AWS RDS PostgreSQL 15.3 | 1 | Multi-AZ, failover automático |
| **Health Check** | HTTP | - | Ruta: `/health-check/`, Puerto: 8080, Intervalo: 2s |
| **Computador Personal** | Apache JMeter | - | 500 usuarios concurrentes |

### Configuración del Health Check

```yaml
Health Check Configuration:
  Enabled: true
  Protocol: HTTP
  Port: 8080
  Path: /health-check/
  Interval: 2 seconds
  Timeout: 1 second
  Healthy Threshold: 2 (2 checks OK para marcar saludable)
  Unhealthy Threshold: 2 (2 fallos para marcar no saludable)
  Expected Status Codes: 200
  Detection Time: max(2 failed checks * 2 sec) = 4 seconds ✓ (< 5 segundos)
```

### Descripción del Experimento

1. **Preparación**
   - Desplegar infraestructura en AWS con 3 instancias EC2 (usuarios, datos, notificaciones)
   - Verificar que todas las instancias están saludables en el ALB
   - Configurar JMeter para simular 500 usuarios concurrentes

2. **Ejecución**
   - Iniciar JMeter con 500 usuarios realizando peticiones constantes al ALB
   - Registrar baseline de latencia y tasa de éxito
   - Esperar 30 segundos de estabilización

3. **Simulación de Falla**
   - **En T=30s:** Detener manualmente una instancia EC2 (simular falla)
   - Registrar timestamp exacto de detención

4. **Medición**
   - **T+2s:** Primer health check falla
   - **T+4s:** Segundo health check falla → Instancia marcada como UNHEALTHY
   - **T+4s:** ALB redirige tráfico a instancias restantes
   - Medir: Tiempo desde T=0 hasta redirección completa (debe ser ≤5s)

5. **Recolección de Métricas**
   - Tiempo de detección de falla (segundos)
   - Número de peticiones fallidas durante failover
   - Porcentaje de pérdida de peticiones (debe ser ≤1%)
   - Latencia promedio ante y después del failover
   - Tasa de éxito (debe mantenerse >99%)

### Criterios de Éxito

✅ **PASS si:**
- Tiempo de recuperación (failover) ≤ 5 segundos
- Porcentaje de peticiones fallidas durante evento ≤ 1%
- Tasa de éxito general ≥ 99%
- ALB redirige el 100% del tráfico a instancias saludables

❌ **FAIL si:**
- Tiempo de recuperación > 5 segundos
- Porcentaje de peticiones fallidas > 1%
- Se pierden peticiones activas

### Monitoreo y Observabilidad

```
CloudWatch Metrics:
- ALB Target Health Status (Healthy/Unhealthy)
- ALB Response Time (target: < 2s promedio)
- ALB Request Count (total requests)
- ALB HTTP 5xx Errors (target: 0)
- EC2 CPU Utilization
- EC2 Network In/Out

CloudWatch Alarms:
- Instancia marcada UNHEALTHY
- Response time > 5 segundos
- HTTP 5xx errors > 10
```

### Recuperación Post-Experimento

1. Reiniciar instancia EC2 detenida
2. Esperar a que pasen health checks (máximo 4 segundos)
3. Verificar que ALB la incluye en rotación
4. Esperar a que vuelva a steady-state
5. Verificar logs de JMeter para validar recuperación

### Notas Técnicas

- Health check en puerto 8080 (diferente del 8000 de la aplicación) para simular independencia
- Intervalo de 2 segundos (más agresivo que 5s recomendado) para detectar fallos rápidamente
- Auto Scaling Group con capacidad de escalar de 3 a 6 instancias (para futuros tests de carga)
- RDS Multi-AZ con automatic failover proporciona resiliencia a nivel de base de datos (independiente del test)
