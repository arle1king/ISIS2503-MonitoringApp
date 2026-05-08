import hashlib
import json
from measurements.models import ConsumoCloud
from measurements.logic.logic_measurement import generate_cost_report


def test_compute_hash_changes_on_modification():
    # Create an in-memory ConsumoCloud-like object
    c = ConsumoCloud(
        recurso='EC2',
        cantidadUtilizadas=10,
        costoPorUnidad=0.5,
        fechaRegistro='2026-05-01T12:00:00',
        idProyecto=1,
        tenant='empresa_a'
    )

    h1 = c.compute_hash()

    # Modify a field and ensure hash changes
    c.cantidadUtilizadas = 20
    h2 = c.compute_hash()

    assert isinstance(h1, str) and len(h1) == 64
    assert h1 != h2, "Hash must change when data changes"


def test_generate_cost_report_validation_flow(monkeypatch):
    # Simulate two records: one valid and one manipulated
    valid = ConsumoCloud(
        recurso='S3',
        cantidadUtilizadas=5,
        costoPorUnidad=1.0,
        fechaRegistro='2026-05-05T10:00:00',
        idProyecto=2,
        tenant='empresa_a'
    )
    manipulated = ConsumoCloud(
        recurso='EC2',
        cantidadUtilizadas=1,
        costoPorUnidad=100.0,
        fechaRegistro='2026-05-10T10:00:00',
        idProyecto=2,
        tenant='empresa_a'
    )

    # Monkeypatch ConsumoCloud.objects.filter to return our list
    class DummyManager:
        def filter(self, **kwargs):
            return [valid, manipulated]

    monkeypatch.setattr(ConsumoCloud, 'objects', DummyManager())

    # Monkeypatch verify_and_log: valid -> (True, None), manipulated -> (False, mocklog)
    def fake_verify_and_log_valid(usuario=None, accion=''):
        return (True, None)

    class MockLog:
        pk = 123

    def fake_verify_and_log_manip(usuario=None, accion=''):
        return (False, MockLog())

    monkeypatch.setattr(valid, 'verify_and_log', fake_verify_and_log_valid)
    monkeypatch.setattr(manipulated, 'verify_and_log', fake_verify_and_log_manip)

    ok, payload = generate_cost_report(2026, 5, tenant='empresa_a', usuario='tester')

    assert ok is False
    assert payload.get('reason') == 'manipulado'
    assert 'log_id' in payload
