from django.utils.deprecation import MiddlewareMixin
from django.conf import settings

class TenantMiddleware(MiddlewareMixin):
    """Extract tenant from Authorization JWT (Auth0) or from header `X-Tenant`.

    Priority: use token claim `tenant` if present; fallback to header `X-Tenant`.
    Sets `request.tenant_key` to the tenant key string.
    """
    def _extract_from_header(self, request):
        return request.META.get('HTTP_X_TENANT')

    def _extract_from_token(self, request):
        # Minimal implementation: if using Django authentication middleware with
        # request.user populated and user has attribute `tenant_key`, prefer it.
        user = getattr(request, 'user', None)
        if user and hasattr(user, 'tenant_key'):
            return getattr(user, 'tenant_key')
        # If using JWT in header without full decoding here, leave None.
        return None

    def process_request(self, request):
        tenant = self._extract_from_token(request)
        if not tenant:
            tenant = self._extract_from_header(request)
        request.tenant_key = tenant or getattr(settings, 'DEFAULT_TENANT', 'public')
