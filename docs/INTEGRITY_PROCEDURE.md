# Procedimiento: Verificación de Integridad para reportes de costos

Resumen
-------
Este documento describe cómo funciona la verificación de integridad implementada en la app `measurements` y cómo ejecutar las comprobaciones y pruebas locales.

Componentes añadidos
--------------------
- `ConsumoCloud` (modelo): representa registros de consumo con campo `hash_sha256`.
- `LogsAuditoria` (modelo): almacena resultados de las verificaciones.
- `ConsumoCloud.compute_hash()`: genera un SHA‑256 determinista del registro.
- `ConsumoCloud.verify_and_log(usuario, accion)`: compara hash actual con almacenado y crea un `LogsAuditoria`.
- `measurements.logic.generate_cost_report(year, month, tenant, usuario)`: valida todos los `ConsumoCloud` del periodo antes de generar el reporte; si detecta manipulación devuelve `('manipulado')`.

Configuración
-------------
Opcionalmente puede subirse cada hash a un bucket S3 inmutable. Para habilitarlo, en `monitoring/settings.py` definir:

- `ENABLE_HASH_UPLOAD=True`
- `S3_BUCKET_HASHES=hashes-inmutables`

Boto3 seguirá la cadena de proveedores de credenciales estándar de AWS (variables de entorno, perfil, IAM role).

Migraciones
-----------
Generar y aplicar migraciones para los nuevos modelos:

```powershell
python manage.py makemigrations measurements
python manage.py migrate
```

Ejecución local y pruebas
-------------------------
- Ejemplos rápidos en `manage.py shell`:

```python
from measurements.models import ConsumoCloud
c = ConsumoCloud(recurso='vm', cantidadUtilizadas=2, costoPorUnidad=10, fechaRegistro='2026-05-01T00:00:00', idProyecto=1)
print(c.compute_hash())
```

- Ejecutar tests unitarios (pytest):

```powershell
pip install -r requirements.txt
pytest tests/integrity_tests -q
```

Notas de despliegue
-------------------
- Para evidencias inmutables a escala de producción, subir los hashes a S3 con Object Lock o a una tabla DynamoDB con versionado y cifrado.
- Registrar y monitorizar fallos de subida de hashes (CloudWatch / Alerts).

Siguientes mejoras recomendadas
------------------------------
- Subir checksum final del reporte a DynamoDB (tabla de checksums) o S3 con Object Lock.
- Añadir un Lambda/EventBridge que valide periódicamente los datos.
- Integrar la verificación en el flujo de generación de reportes (task Celery o vista HTTP) para rechazar automáticamente reportes manipulados.
