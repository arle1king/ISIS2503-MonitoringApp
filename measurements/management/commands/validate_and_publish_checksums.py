from django.core.management.base import BaseCommand
from django.conf import settings
from measurements.models import ConsumoCloud
from variables.models import Tenant
import hashlib, json

try:
    import boto3
except Exception:
    boto3 = None


class Command(BaseCommand):
    help = 'Validate ConsumoCloud hashes for a tenant and publish report checksum to S3 (or DynamoDB)'

    def add_arguments(self, parser):
        parser.add_argument('--tenant', required=True, help='Tenant key to validate')
        parser.add_argument('--year', type=int, required=True)
        parser.add_argument('--month', type=int, required=True)

    def handle(self, *args, **options):
        tenant_key = options['tenant']
        year = options['year']
        month = options['month']

        self.stdout.write(f'Validating tenant={tenant_key} period={year}-{month:02d}')

        # Fetch records
        registros = ConsumoCloud.objects.filter(tenant__key=tenant_key, fechaRegistro__year=year, fechaRegistro__month=month)

        manipulated = []
        payload = {'items': []}
        grand_total = 0.0

        for r in registros:
            cur_hash = r.compute_hash() if hasattr(r, 'compute_hash') else ''
            ok = (cur_hash == r.hash_sha256)
            payload['items'].append({'recurso': r.recurso, 'cost': float(r.cantidadUtilizadas) * float(r.costoPorUnidad), 'ok': ok})
            if not ok:
                manipulated.append(r.id)
            grand_total += float(r.cantidadUtilizadas) * float(r.costoPorUnidad)

        payload['TOTAL'] = grand_total
        report_checksum = hashlib.sha256(json.dumps(payload, sort_keys=True).encode('utf-8')).hexdigest()

        if manipulated:
            self.stdout.write(self.style.ERROR(f'Found manipulated records: {manipulated}'))
        else:
            self.stdout.write(self.style.SUCCESS('All records valid'))

        # Publish checksum to S3 if configured
        bucket = getattr(settings, 'S3_BUCKET_HASHES', '')
        if boto3 and bucket:
            key = f"{tenant_key}/report_{year:04d}{month:02d}.checksum"
            s3 = boto3.client('s3')
            s3.put_object(Bucket=bucket, Key=key, Body=report_checksum.encode('utf-8'))
            self.stdout.write(self.style.SUCCESS(f'Uploaded checksum to s3://{bucket}/{key}'))
        else:
            self.stdout.write('S3 not configured or boto3 missing; skipping upload')

        # Optionally we could write to DynamoDB — omitted for brevity
        self.stdout.write(f'Checksum: {report_checksum}')
