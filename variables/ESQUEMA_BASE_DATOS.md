Esquema de base de datos (Patrón multi-tenant por esquema)
==========================================================

Resumen
------
Este archivo documenta el patrón de base de datos multi-tenant por esquema y las tablas clave usadas por los ASR (Disponibilidad, Confidencialidad, Integridad).

Estructura general
------------------
- Base de datos RDS PostgreSQL
- Esquemas por cliente/empresa: `empresa_a`, `empresa_b`, `empresa_c`, ...
- Esquema público `public` para tablas globales: `tenants`, `roles_globales`, `logs_auditoria` (si aplica)

Estructura (ejemplo)
--------------------
📦 Base de datos RDS
│
├── 📁 empresa_a
│   ├── 📄 usuarios
│   ├── 📄 proyectos
│   ├── 📄 consumo_cloud
│   └── 📄 reportes
│
├── 📁 empresa_b
│   ├── 📄 usuarios
│   ├── 📄 proyectos
│   ├── 📄 consumo_cloud
│   └── 📄 reportes
│
└── 📁 public
    ├── 📄 tenants
    ├── 📄 roles_globales
    └── 📄 logs_auditoria

Tabla: `consumo_cloud` (por esquema, ejemplo: empresa_a.consumo_cloud)
------------------------------------------------------------------
SQL de ejemplo:

CREATE TABLE consumo_cloud (
    idConsumo SERIAL PRIMARY KEY,
    recurso VARCHAR(100),
    cantidadUtilizadas FLOAT,
    costoPorUnidad FLOAT,
    fechaRegistro TIMESTAMP,
    idProyecto INT,
    hash_sha256 VARCHAR(64) NOT NULL
);

Notas:
- `hash_sha256` contiene el SHA-256 del payload del registro (representación canónica JSON).
- Los hashes también se almacenan en un bucket S3 inmutable (opcional) para evidencia externa.

Tabla de logs de auditoría (en `public` o `audit` schema)
--------------------------------------------------------
SQL de ejemplo:

CREATE TABLE logs_auditoria (
    idLog SERIAL PRIMARY KEY,
    fecha TIMESTAMP DEFAULT NOW(),
    usuario VARCHAR(100),
    accion VARCHAR(50),
    tabla_afectada VARCHAR(50),
    idRegistro INT,
    hash_esperado VARCHAR(64),
    hash_real VARCHAR(64),
    resultado VARCHAR(20) -- 'valido' / 'manipulado'
);

Notas y recomendaciones
-----------------------
- Aislamiento por esquema: cada tenant tiene su propio schema (ej. `empresa_a`). Esto simplifica permisos y el enrutamiento en ProxySQL.
- ProxySQL: configurar reglas que enruten queries según el tenant extraído del JWT/claims o del usuario. Ejemplo en `docs/ASR2_ESPECIFICADOR_Confidencialidad.md`.
- Impedir acceso directo a RDS: el security group de RDS debe aceptar conexiones solo desde ProxySQL.
- Auditoría inmutable: además de `logs_auditoria` en RDS, subir copias de logs o hashes a S3 con Object Lock o almacenar checksums en DynamoDB para inmutabilidad reforzada.
- Verificación de integridad: cada registro de `consumo_cloud` debe tener su `hash_sha256`; la aplicación debe calcular y validar este hash antes de generar reportes.

Almacenamiento inmutable de hashes (S3)
--------------------------------------
Bucket de ejemplo: `hashes-inmutables/`

Estructura:

hashes-inmutables/
├── empresa_a/
│   ├── consumo_123.hash
│   ├── consumo_124.hash
├── empresa_b/
└── logs/

Cada archivo `.hash` contiene el SHA-256 (texto plano) del registro correspondiente.

Uso en la aplicación
--------------------
- Modelos Django: añadir campo `tenant` si es útil para pruebas locales; en producción use el tenant extraído de claims y no acepte tenant desde el cliente.
- Uso recomendado:
  - `ConsumoCloud.compute_hash()` para obtener SHA-256 canónico.
  - `ConsumoCloud.verify_and_log()` para comparar hash actual vs almacenado y escribir en `logs_auditoria`.
  - Subir el hash a S3 si `ENABLE_HASH_UPLOAD` está activado en `monitoring/settings.py`.

Migraciones y despliegue
------------------------
- Crear migraciones Django para las tablas que se gestionen desde la app.
- Las operaciones de creación de schemas (CREATE SCHEMA empresa_x) se suelen ejecutar desde Terraform o scripts de inicialización de base de datos (ver `terraform/modules/confidentiality` y `terraform/modules/proxysql`).

Referencias en el repo
----------------------
- `docs/ASR2_ESPECIFICADOR_Confidencialidad.md` — reglas ProxySQL y pruebas.
- `measurements/models.py` — implementación `ConsumoCloud`, `LogsAuditoria`, hashing y upload opcional a S3.
- `monitoring/settings.py` — flags `ENABLE_HASH_UPLOAD`, `S3_BUCKET_HASHES`.

Si quieres, puedo:
- Generar SQL de creación de schemas y tablas listo para ejecutar (por esquema).
- Crear un script de inicialización que cree `empresa_a`, `empresa_b`, `empresa_c` y las tablas base.
- Añadir una migración o management command para crear esquemas y tablas en RDS.

Dime qué opción prefieres y lo genero ahora.