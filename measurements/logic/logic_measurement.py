from ..models import Measurement, ConsumoCloud
from django.db.models import Sum, F, ExpressionWrapper, FloatField
from datetime import datetime, timedelta


def get_measurements():
    queryset = Measurement.objects.all().order_by('-dateTime')[:10]
    return (queryset)


def create_measurement(form):
    measurement = form.save()
    measurement.save()
    return ()


def generate_cost_report(year: int, month: int, tenant: str = 'public', usuario: str = ''):
    """Genera un reporte de costos para el mes indicado.

    Paso previo: valida integridad de cada registro `ConsumoCloud` del periodo.
    Si se detecta alguna manipulación, retorna (False, {'reason': 'manipulado', 'log': <LogsAuditoria>}).

    Retorna: (True, { 'report': {...}, 'checksum': 'sha256' })
    """
    # Determinar rango de fechas para el mes
    start = datetime(year=year, month=month, day=1)
    if month == 12:
        end = datetime(year=year + 1, month=1, day=1)
    else:
        end = datetime(year=year, month=month + 1, day=1)

    # Filtrar registros del tenant y período
    registros = ConsumoCloud.objects.filter(tenant=tenant, fechaRegistro__gte=start, fechaRegistro__lt=end)

    # Validar integridad por registro
    for registro in registros:
        valid, log = registro.verify_and_log(usuario=usuario, accion='pre_report_validation')
        if not valid:
            return (False, {'reason': 'manipulado', 'log_id': log.pk})

    # Si todos válidos, agregar y construir reporte
    # Agrupar por recurso (servicio) y sumar costos — usar expresiones ORM seguras
    try:
        expr = ExpressionWrapper(F('costoPorUnidad') * F('cantidadUtilizadas'), output_field=FloatField())
        summary = registros.values('recurso').annotate(total_cost=Sum(expr))
    except Exception:
        summary = None

    # Fallback manual aggregation (in case DB expression unsupported)
    totals = {}
    grand_total = 0.0
    for r in registros:
        cost = float(r.cantidadUtilizadas) * float(r.costoPorUnidad)
        totals.setdefault(r.recurso, 0.0)
        totals[r.recurso] += cost
        grand_total += cost

    report = {
        'period': f"{year:04d}-{month:02d}",
        'tenant': tenant,
        'items': [{'service': k, 'cost': v} for k, v in totals.items()],
        'TOTAL': grand_total
    }

    # Checksum del reporte
    import json, hashlib
    checksum = hashlib.sha256(json.dumps(report, sort_keys=True).encode('utf-8')).hexdigest()

    return (True, {'report': report, 'checksum': checksum})