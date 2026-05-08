from django.http import JsonResponse
from django.db import connections

def health(request):
    """Lightweight health endpoint for ALB health checks.

    Returns 200 and a small JSON. Optionally checks database connectivity.
    Use query param `db=1` to include a quick DB ping.
    """
    ok = True
    details = {'app': 'ok'}
    if request.GET.get('db') == '1':
        try:
            # simple db check on default
            with connections['default'].cursor() as cur:
                cur.execute('SELECT 1')
                cur.fetchone()
            details['db'] = 'ok'
        except Exception as e:
            ok = False
            details['db'] = f'error: {str(e)}'

    status = 200 if ok else 503
    return JsonResponse(details, status=status)
