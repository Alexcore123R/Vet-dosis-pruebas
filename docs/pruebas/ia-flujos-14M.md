# Flujos de asistencia IA — 14M

Aplicar `supabase/proposed/14M_ai_assisted_workflows.sql` después de 14L y 14J antes de instalar el APK nuevo. Se reutilizan el proveedor, el consentimiento de envío a IA y el chat existentes; esta entrega no requiere una Edge Function adicional. El SQL se entrega para aplicación manual en Supabase.

## Comprobación en la app

1. **Promociones → Pedir ideas a la IA.** Capturar servicio/producto, fechas, descuento opcional y condiciones. Solicitar las tres opciones, devolver la respuesta desde el chat y elegir una. Verificar que título, mensaje y condiciones se abren en el formulario editable y que fechas y descuento corresponden a los datos capturados. Guardar y volver a abrir. Compartir incluye las condiciones completas.
2. **Agenda → Recordatorio / seguimiento y autorización.** Usar una cita vinculada a paciente y tutor. Sin autorización registrada no se habilita el canal. Registrar la fuente de autorización con `patient.write`. Confirmar que autorizar recordatorios no autoriza seguimiento ni promociones. Elegir el propósito, redactar manualmente o con IA, revisar y abrir WhatsApp/correo; el envío final se confirma fuera de la app.
3. Revocar el permiso desde otra sesión antes de abrir WhatsApp. La comprobación nueva debe impedir abrirlo. Cambiar la cita debe exigir actualizar y revisar el mensaje.
4. **Formatos → borrador → Preparar notas, indicaciones o alta con IA.** Seleccionar campos, escribir o dictar las notas del profesional, detener el micrófono y revisar la transcripción. Generar y devolver el borrador, corregir cada campo y marcar la revisión para incorporarlo. Guardar, revisar PDF y continuar con las firmas del flujo existente. El asistente no modifica identidad ni firmas y no se ofrece en documentos ya firmados. El micrófono requiere la disponibilidad y los permisos del dispositivo.
5. **Inventario o Caja → Analizar existencias, caducidades y ventas.** Verificar stock utilizable, lotes de los próximos 90 días y vencidos por separado. Comparar las ventas netas de dos periodos de 30 días; las devoluciones se contabilizan por su fecha y pueden producir cantidades netas negativas. Pedir propuestas y revisarlas antes de registrar pedidos, precios o promociones.
6. Con acceso de inventario pero sin `sales.read`, comprobar que no aparecen ventas ni importes. Sin proveedor IA configurado puede revisarse la evidencia y capturarse texto manualmente; generar respuestas requiere un proveedor disponible en el asistente existente.

## Validación reproducible

- `flutter analyze`
- `flutter test --timeout 5m`
- `bash supabase/tests/run_permission_clinic_operations.sh supabase/proposed/14J_clients_promotions.sql supabase/proposed/14M_ai_assisted_workflows.sql supabase/tests/ai_assisted_workflows.sql`

Las pruebas usan respuestas sintéticas para comprobar selección y traslado de borradores; no simulan resultados de una cuenta real del proveedor IA.
