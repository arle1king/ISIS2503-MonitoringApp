-- SQL inicial para crear schemas y tablas base (ejecutar con psql conectado al RDS)

-- Crear esquemas de ejemplo
CREATE SCHEMA IF NOT EXISTS empresa_a;
CREATE SCHEMA IF NOT EXISTS empresa_b;
CREATE SCHEMA IF NOT EXISTS empresa_c;

-- Tabla consumo_cloud (ejemplo en cada schema)
CREATE TABLE IF NOT EXISTS empresa_a.consumo_cloud (
    idConsumo SERIAL PRIMARY KEY,
    recurso VARCHAR(100),
    cantidadUtilizadas FLOAT,
    costoPorUnidad FLOAT,
    fechaRegistro TIMESTAMP,
    idProyecto INT,
    hash_sha256 VARCHAR(64) NOT NULL
);

CREATE TABLE IF NOT EXISTS empresa_b.consumo_cloud (
    idConsumo SERIAL PRIMARY KEY,
    recurso VARCHAR(100),
    cantidadUtilizadas FLOAT,
    costoPorUnidad FLOAT,
    fechaRegistro TIMESTAMP,
    idProyecto INT,
    hash_sha256 VARCHAR(64) NOT NULL
);

-- Tabla logs de auditoría en schema public (inmutable recomendada en S3/DynamoDB)
CREATE TABLE IF NOT EXISTS public.logs_auditoria (
    idLog SERIAL PRIMARY KEY,
    fecha TIMESTAMP DEFAULT NOW(),
    usuario VARCHAR(100),
    accion VARCHAR(50),
    tabla_afectada VARCHAR(50),
    idRegistro INT,
    hash_esperado VARCHAR(64),
    hash_real VARCHAR(64),
    resultado VARCHAR(20)
);

-- Tabla de tenants en public
CREATE TABLE IF NOT EXISTS public.tenants (
    id SERIAL PRIMARY KEY,
    key VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200) NOT NULL
);

-- Tabla reportes en public (registro de checksums finales)
CREATE TABLE IF NOT EXISTS public.reportes (
    id SERIAL PRIMARY KEY,
    tenant_key VARCHAR(100) NOT NULL,
    report_id VARCHAR(100) NOT NULL,
    generated_at TIMESTAMP DEFAULT NOW(),
    checksum VARCHAR(64) NOT NULL,
    payload JSONB,
    UNIQUE (tenant_key, report_id)
);
