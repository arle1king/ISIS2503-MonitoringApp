Tests: ejecución y recomendaciones
=================================

Resumen rápido
- Los tests que interactúan con AWS están marcados como `integration` y se omitirá su ejecución por defecto.
- Ejecuta los tests unitarios rápidamente con `pytest -m "not integration"`.

Hacer tests unitarios (rápido)

1. Crear entorno e instalar dependencias de prueba:

```bash
python -m venv .venv
.venv/Scripts/activate    # Windows
pip install -r requirements-test.txt
```

2. Ejecutar solo unit tests:

```bash
pytest -q -m "not integration"
```

Habilitar tests de integración (AWS)
- Para ejecutar las pruebas que tocan AWS, ejecute con la variable de entorno o la opción:

```bash
export RUN_AWS_INTEGRATION=1        # o en Windows: setx RUN_AWS_INTEGRATION 1 (nueva shell)
pytest -q
# O usar la opción:
pytest -q --run-aws
```

Recomendaciones
- No ejecute las pruebas de integración contra entornos de producción.
- Para la mayoría de los casos, prefiera mockear servicios AWS con `moto` o `botocore` Stubber.
- Las pruebas de integridad (hash) están diseñadas como unitarias y deben ejecutarse por defecto.
