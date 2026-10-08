# M14 — Pagos, soporte, producto e inicio guiado

## Pantallas

- **Planes, pagos y beneficios:** catálogo existente, ciclo mensual/anual, solicitud de interés, checkout externo seguro cuando se habilite y un historial de pagos confirmados del servidor. No almacena tarjeta/CVV. Los pagos de suscripción se distinguen del cobro a clientes en caja. No convierte un regreso del navegador en confirmación de pago.
- **Producto y costos:** descripción de herramientas y precios propuestos, disponible también antes del login. Identifica funciones e integraciones pendientes, consumo de IA aparte y alcance individual/clínica. Esta página está dentro de la app; no se ha publicado una campaña o sitio externo.
- **Inicio guiado:** invitación de primera visita y siete pasos reabribles. Guarda progreso por usuario/espacio únicamente en el dispositivo. Marcar un paso no verifica la configuración, no crea pacientes y no concede permisos. Se puede posponer.
- **Ayuda, contacto y reportes:** errores, dudas, pagos o sugerencias; seguimiento y conversación privada con soporte. Hasta 20 solicitudes por día, 200 mensajes y cinco adjuntos por reporte, cada uno de hasta 5 MiB: JPEG, PNG, PDF o TXT. Los archivos usan un bucket privado y enlaces temporales de 60 segundos, sin sobrescritura. No se capturan errores ni datos del dispositivo automáticamente.

## IA para ayuda

El botón prepara un chat privado de ayuda con el título y descripción del borrador. El usuario puede editarlo y selecciona clave/modelo y consentimiento en la pantalla existente antes de enviarlo al proveedor. No se envían adjuntos automáticamente, ni se toma contexto clínico por defecto. La IA no ejecuta acciones, no afirma enviar el reporte y no reemplaza soporte humano. El reporte humano se puede enviar sin usar IA ni contratar un proveedor.

## Privacidad y atención humana

Los operadores se habilitan exclusivamente en `private.support_operators` desde administración de servidor; nunca desde el cliente. Los reportes pertenecen al usuario que los creó; requiere pertenencia actual a su espacio. Un admin de clínica no accede a los reportes de otros integrantes. `support_queue_server`, `support_detail_server` y `support_reply_server` son exclusivos del servicio global de soporte. La app del cliente no puede responder como humano. Cada mensaje conserva origen y hora del servidor; los mensajes no se editan por el cliente. Los reintentos de creación/mensajes usan claves de operación para evitar duplicados.

El usuario revisa y autoriza compartir el reporte con soporte. No debe incluir claves, tarjetas o datos identificables de pacientes/propietarios/personal. Este texto no sustituye un aviso de privacidad final. No hay análisis automático de malware ni redacción automática de adjuntos: debe revisarse la política operativa antes de atender documentos reales.

**Atención humana todavía sin activar:** ya existe un panel de operadores con cola, conversación, adjuntos y respuestas, protegido por asignaciones globales de servidor y auditoría de lectura/respuesta. El rol admin de clínica no concede ese acceso. Faltan asignar personas reales, horarios, responsables, política de conservación, aviso de privacidad y canal de notificaciones. El servidor ya dispone de cola y respuesta; no se ha conectado personal real ni prometido tiempos de respuesta. Los estados son pendiente de humano, en revisión, esperando al usuario y resuelto; se actualizan manualmente, sin push/email automático.

`SUPPORT_EMAIL` y `SUPPORT_WHATSAPP` son configuración pública opcional de compilación. El segundo usa número internacional solo con dígitos. Abren el correo/WhatsApp del usuario para que él envíe, sin mensajes automáticos ni datos del reporte añadidos al enlace. Sin configuración, la app informa que faltan los contactos directos.

## Instalación y límites

Aplicar `supabase/adaptations/existing_support_m14.sql` después de M13 y con Supabase Storage disponible. Añade tablas/RPC/bucket sin reconstruir las existentes y `plan_payment_history` para el admin de su espacio. Actualizar app y configurar contacto después de definir los datos reales. No se ha aplicado al Supabase remoto.

Los adjuntos de soporte tienen presupuesto separado de los datos de clínica: el máximo por reporte es 25 MiB. Faltan cuotas operativas globales, limpieza de cargas fallidas/reservas y archivos vencidos, análisis de seguridad de adjuntos y exportación de soporte dentro de M11. Hoy pueden necesitar mantenimiento de servidor si la carga se interrumpe. No se incluyen secretos en exportaciones existentes.

Pruebas: `bash supabase/tests/run.sh ai_plans` añade aislamiento de tickets/archivos, restricción de respuestas humanas e idempotencia; `flutter test` incluye la página en teléfono, progreso separado por espacio y limpieza de datos tras pérdida de acceso. Las pruebas reales de pagos, proveedores IA, descargas/contactos y dispositivos siguen pendientes.
