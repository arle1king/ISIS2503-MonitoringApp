from django.db import models
from variables.models import Variable
from django.conf import settings
import hashlib
import json
import datetime


class Measurement(models.Model):
    variable = models.ForeignKey(Variable, on_delete=models.CASCADE, default=None)
    value = models.FloatField(null=True, blank=True, default=None)
    unit = models.CharField(max_length=50)
    place = models.CharField(max_length=50)
    dateTime = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return '%s %s' % (self.value, self.unit)


class ConsumoCloud(models.Model):
    recurso = models.CharField(max_length=100)
    cantidadUtilizadas = models.FloatField()
    costoPorUnidad = models.FloatField()
    fechaRegistro = models.DateTimeField()
    idProyecto = models.IntegerField()
    hash_sha256 = models.CharField(max_length=64)
    # optional tenant identifier (if using schema-per-tenant routing elsewhere)
    tenant = models.CharField(max_length=100, default='public')

    class Meta:
        verbose_name = 'Consumo Cloud'
        verbose_name_plural = 'Consumos Cloud'

    def __str__(self):
        return f"{self.recurso} - {self.cantidadUtilizadas} ({self.fechaRegistro.isoformat()})"

    def _canonical_payload(self):
        # Build a deterministic representation for hashing
        payload = {
            'recurso': self.recurso,
            'cantidadUtilizadas': float(self.cantidadUtilizadas),
            'costoPorUnidad': float(self.costoPorUnidad),
            'fechaRegistro': self.fechaRegistro.isoformat() if isinstance(self.fechaRegistro, (datetime.datetime,)) else str(self.fechaRegistro),
            'idProyecto': int(self.idProyecto)
        }
        return json.dumps(payload, sort_keys=True, separators=(',', ':'))

    def compute_hash(self):
        data = self._canonical_payload().encode('utf-8')
        return hashlib.sha256(data).hexdigest()

    def save(self, *args, **kwargs):
        if not self.hash_sha256:
            self.hash_sha256 = self.compute_hash()
        super().save(*args, **kwargs)
        # Optionally upload the hash to immutable storage if configured
        if getattr(settings, 'ENABLE_HASH_UPLOAD', False):
            try:
                _upload_hash_to_s3_record(self)
            except Exception:
                # Do not block on upload failures; they should be monitored separately
                pass

    def verify_and_log(self, usuario=None, accion='verificacion'):
        """Compute current hash, compare with stored, and create an audit log entry.

        Returns: (is_valid: bool, LogsAuditoria instance)
        """
        current_hash = self.compute_hash()
        resultado = 'valido' if current_hash == self.hash_sha256 else 'manipulado'
        log = LogsAuditoria.objects.create(
            usuario=usuario or '',
            accion=accion,
            tabla_afectada='consumo_cloud',
            idRegistro=self.pk,
            hash_esperado=self.hash_sha256,
            hash_real=current_hash,
            resultado=resultado
        )
        return (resultado == 'valido', log)


class LogsAuditoria(models.Model):
    fecha = models.DateTimeField(auto_now_add=True)
    usuario = models.CharField(max_length=100)
    accion = models.CharField(max_length=50)
    tabla_afectada = models.CharField(max_length=50)
    idRegistro = models.IntegerField()
    hash_esperado = models.CharField(max_length=64)
    hash_real = models.CharField(max_length=64)
    resultado = models.CharField(max_length=20)  # 'valido' / 'manipulado'

    class Meta:
        verbose_name = 'Log Auditoria'
        verbose_name_plural = 'Logs Auditoria'

    def __str__(self):
        return f"[{self.fecha.isoformat()}] {self.tabla_afectada}:{self.idRegistro} -> {self.resultado}"


# Lightweight S3 uploader stub. Uses boto3 if available and settings define S3_BUCKET_HASHES.
def _upload_hash_to_s3_record(record: ConsumoCloud):
    bucket = getattr(settings, 'S3_BUCKET_HASHES', None)
    if not bucket:
        return False
    try:
        import boto3
    except Exception:
        return False
    key_prefix = f"{record.tenant}/"
    key_name = f"{key_prefix}consumo_{record.pk}.hash"
    s3 = boto3.client('s3')
    s3.put_object(Bucket=bucket, Key=key_name, Body=record.hash_sha256.encode('utf-8'))
    return True