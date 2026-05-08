from django.db import models
from django.utils import timezone


class Variable(models.Model):
    name = models.CharField(max_length=50)

    def __str__(self):
        return '{}'.format(self.name)


class Tenant(models.Model):
    """Represents a tenant / company schema."""
    key = models.CharField(max_length=100, unique=True)
    display_name = models.CharField(max_length=200)

    def __str__(self):
        return f"{self.display_name} ({self.key})"


class Usuario(models.Model):
    """Lightweight user record tied to a tenant."""
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    username = models.CharField(max_length=150)
    email = models.EmailField(null=True, blank=True)
    role = models.CharField(max_length=50, default='user')

    def __str__(self):
        return f"{self.username}@{self.tenant.key}"


class Proyecto(models.Model):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)

    def __str__(self):
        return f"{self.name} ({self.tenant.key})"


class ConsumoCloud(models.Model):
    """Cost consumption record (per tenant)."""
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    recurso = models.CharField(max_length=100)
    cantidadUtilizadas = models.FloatField()
    costoPorUnidad = models.FloatField()
    fechaRegistro = models.DateTimeField()
    proyecto = models.ForeignKey(Proyecto, on_delete=models.SET_NULL, null=True, blank=True)
    hash_sha256 = models.CharField(max_length=64, blank=True)

    def __str__(self):
        return f"{self.recurso} - {self.tenant.key} - {self.fechaRegistro.date()}"


class Reporte(models.Model):
    """Generated report record storing report payload and checksum."""
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    report_id = models.CharField(max_length=100)
    generated_at = models.DateTimeField(default=timezone.now)
    checksum = models.CharField(max_length=64)
    payload = models.JSONField()

    class Meta:
        unique_together = ('tenant', 'report_id')

    def __str__(self):
        return f"Reporte {self.report_id} ({self.tenant.key})"

