# Identidad visual y búsqueda

Implementación preparada en la app:
- Escáner flotante encima de IA y soporte, filtrado por el acceso actual al inventario.
- Buscador de apartados y herramientas en Inicio, tolerante a acentos. No busca expedientes ni sustituye la búsqueda de inventario.
- Foto o icono personal en Mi cuenta y clínicas; almacenamiento local por identificador de cuenta, sin sincronización. La foto se decodifica y vuelve a codificar como PNG, con límites de tamaño. Un icono sustituye la foto.
- Nombre real de la clínica activa y logo en Inicio y perfil; consulta el membrete existente, sin reutilizar información de otra clínica.
- Administración abre el editor existente de logo/membrete desde el perfil. Mantiene la vista previa obligatoria y el versionado. Requiere una plantilla disponible para la vista previa.
- Los PDF de formatos que ya usan el membrete conservan su implementación. No se reescriben PDF históricos. Este cambio no agrega imágenes a CSV, XLSX, respaldos ni a todos los otros exportadores.

Sin migraciones ni cambios remotos. El nombre mostrado viene de la membresía existente; editar el texto del membrete no renombra la clínica.

## Decisiones de esquema pendientes de aprobación

1. Identidad visible para todo miembro: RPC de solo lectura, limitada a la clínica activa y membresía vigente, que devuelva exclusivamente nombre y logo. Hoy `form_branding` solo permite admin, MVZ y auxiliar; los demás ven nombre e icono de clínica. No ampliar acceso a documentos clínicos.
2. Avatar sincronizado: bucket privado para imágenes personales, ruta por auth.uid(), límite de tamaño/tipo y políticas para que solo el dueño lea/escriba/elimine. Tabla de perfil con selección foto/icono y clave del objeto; URLs temporales, sin guardar URLs públicas permanentes. La migración desde el avatar local sería explícita.
3. Exportaciones adicionales: revisar cada exportador para incorporar identidad donde el formato lo permita; conservar estructura de datos, firma/hash y documentos ya emitidos. XLSX real sigue siendo una tarea aparte.

La caducidad beta no elimina estas imágenes ni otros datos automáticamente. No se cambian permisos clínicos ni habilitación profesional.
