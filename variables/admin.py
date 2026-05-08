from django.contrib import admin
from . models import Variable, Tenant, Usuario, Proyecto, ConsumoCloud, Reporte

admin.site.register(Variable)
admin.site.register(Tenant)
admin.site.register(Usuario)
admin.site.register(Proyecto)
admin.site.register(ConsumoCloud)
admin.site.register(Reporte)