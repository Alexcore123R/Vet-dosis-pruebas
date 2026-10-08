[Avance por bloques y dependencias finales](avance-pendientes.md).

[Revisión completa del 8 de octubre: correcciones y prioridades](revision-plataforma-2026-10-08.md).

# Pendientes para la revisión final

Lista central actualizada tras M9–M11 y referencias de pagos. Las comprobaciones locales no sustituyen la instalación remota, la revisión clínica ni las pruebas de dispositivos. No se han creado cuentas, pacientes, firmas o movimientos reales para probar.

| Área | Pendiente | Momento/dependencia |
|---|---|---|
| Supabase | Revisar esquema real, respaldo y dependencias; aplicar una sola vez las adaptaciones pendientes M3/M4/M5/formatos/M6/M8, ajuste de entregas/aplicaciones y Storage de fotos y desplegar `forms-pdf` | Revisión integrada final |
| Acceso M2 | Registro, correo de confirmación, Google OAuth, membresías, logout y aislamiento con cuentas distintas | Configuración y pruebas finales |
| Equipo M2 | Administración de integrantes, cambios de rol, bajas y revocación de invitaciones implementados localmente para el esquema existente; instalar `existing_team_management.sql` y probar cuentas reales | Integración final |
| Datos clínicos M3/M7 | Catálogo de dosis y concentraciones comerciales, protocolos, rangos de constantes, factores específicos y tiempos de retiro: completar fuentes y verificar versiones | Datos proporcionados/revisión MVZ; no rellenar con ejemplos |
| Normativa M6 | Clasificación por producto, requisitos de receta/reporte y fuentes vigentes; habilitación profesional revisada en servidor | Antes de actos reservados reales |
| Offline | Cifrado/caché clínica y adaptadores de sincronización por módulo, resolución de conflictos y permisos tras revocación | Trabajo adicional; hoy los datos clínicos requieren conexión |
| M4 | Verificar dictado/permisos micrófono, impresión, mensajes y recordatorios en teléfonos; automatizaciones de recordatorio requieren backend/proveedor | Dispositivos e integración final |
| Hospitalización M5 | Sonido/permisos, app cerrada, reinicio, batería y Focus; capacidad de avisos; push para cancelar avisos remotos sin abrir app | Android/iPhone reales y backend si se añade push |
| Hospitalización M5 | Consulta de altas y cambios de jaula | Iteración de operación |
| Formatos | Revisar textos propios, cláusulas y aviso de privacidad; membrete/logo, consentimiento y campos específicos de eutanasia con la clínica | Antes de firmar documentos reales |
| PDF/firmas | Auth + Edge Function + DB, PDF exacto revisado, compartir/imprimir en Android/iPhone y navegadores; revocación concurrente de permisos | Prueba integrada final |
| M6 | Resolver incidencias de frascos después del cierre con un flujo explícito, sin modificar originales ni forzar reporte completo | Iteración antes de operación real de esos casos |
| M6/M7 | Vincular un resultado clínico verificado a receta/aplicación sin duplicar medicación ni omitir revisión; editor/importación M7 | Después de fuentes reales y definición del flujo |
| M8 | Inventario/POS/corte implementados localmente; falta instalación real, conciliación legacy, inventario personal, actualización de referencias farmacológicas, devoluciones parciales y XLSX | Revisión integrada; hoy exportación CSV para Excel |
| M8: ajuste de flujo | Devolución física de tickets separados y rectificación contable de aplicaciones corregidas o costos pendientes; probar recepción/auxiliar con cuentas reales | Revisión integrada; el cobro no valida el acto clínico ni vuelve a descontar medicamento |
| M8/M9 | Catálogo de servicios y reglas de comisión (%/bono), recepción de servicios con reglas autorizadas | M9; hoy captura manual por admin |
| IA/cámara | Escáner de códigos y fotos implementados: probar cámara/galería/Storage en dispositivos; faltan OCR, IA de pedidos/asistencia/transcripción y comparación de mercado | Integraciones externas con revisión, sin inventar datos extraídos |
| M9–M11 | Implementados localmente con límites descritos abajo; instalación y pruebas integradas pendientes | Revisión final |
| WhatsApp/SMS | `wa.me` es envío manual. Automatización de WhatsApp Business al final si se contrata API; SMS requiere proveedor | Contratación/configuración externa |
| Drive | Conectar respaldo y probar restauración/exportación completa sin exponer datos sensibles | M11 e integración final |
| Plataformas | Compilar y probar Android e iOS (macOS/Xcode para iOS); cámara, audio, PDF y comportamiento de alarmas | Pruebas finales reales |
| GitHub/publicación | Guardar código en repositorio, verificaciones y despliegue web; revisar configuración pública versus secretos | Paso final acordado, todavía sin publicación |

Estado actual: M1–M11 y formatos tienen implementaciones locales con el alcance descrito en sus documentos. Los módulos y conexiones pendientes no se presentan como operativos. M7 no exige otra migración de base de datos.

Actualización M9–M11 (8 de octubre): ya existen pantallas, repositorios y adaptaciones SQL aditivas para operación, checado y estadísticas/exportación operacional. Aplicar, después de M8 workflow, `existing_operations_m9.sql`, `existing_attendance_m10.sql` y `existing_statistics_m11.sql` (requiere también M3), y luego `existing_payment_references.sql`.

Pendientes específicos de estas entregas:
- **M9:** vinculación de citas al expediente, reprogramación/cancelación con motivo y nombres visibles implementados localmente; instalar las extensiones de agenda e historial y revisar agenda/comisiones con usuarios reales. Mensajería es consulta/actualización manual, sin push ni Realtime todavía. Servicios y agenda no conceden permiso para actos clínicos.
- **M10:** validar cámara, precisión y permisos de ubicación en Android/iPhone/web (HTTPS), QR al cambiar de app, cambios de configuración, consentimiento y conservación con la clínica. GPS no garantiza presencia ante suplantación. La corrección implementada anexa hora y motivo; registro manual de checados omitidos y cambios de dirección requieren un flujo adicional revisado.
- **M11:** Drive automático, restauración real ensayada y exportación por lotes; cifrado de respaldo operacional y revisión de archivos implementados localmente. Exportación por lotes pendiente para archivos mayores de 50 MiB sin cifrar. La exportación operacional incluye históricos y sus PDF, fotos de inventario y catálogos versionados; excluye secretos, firmas reutilizables y fichas médicas ajenas. El respaldo integral del servidor debe implementarse sin ampliar por accidente el acceso a esos datos. Verificar un hash comprueba integridad, no identidad del emisor ni recuperabilidad.
- **M11:** las alarmas clínicas de primer plano siguen usando M5; push y automatización WhatsApp Business/SMS continúan pendientes según proveedor.

- **Cobros/pagos:** referencias de efectivo, transferencia y tarjeta y conciliación manual implementadas. Faltan cuentas por proveedor/clínica, webhooks verificados, pasarelas Stripe/PayPal, importación de extractos, pagos divididos/anticipos, devolución por plataforma y enlace de egresos con movimientos de caja. [Alcance](cobros-pagos-integraciones.md). No se eligió banco ni se conectó una cuenta real.

- **M12:** instalar SQL/Edge Function y secreto AES; probar cuentas/modelos reales, privacidad por rol, cuotas y revocación concurrente. Faltan rotación de claves, contexto más amplio, streaming y conexiones de OCR/dictado/pedidos. El contexto revocado no puede retirarse de un proveedor que ya lo recibió.
- **M13:** validar precios, límites y presupuesto; catálogo sin publicar y cobros apagados. Instalar adaptaciones antes de usar la nueva consulta de membresías. Faltan portal/cancelación, devoluciones, prorrateo, impagos, CFDI/términos y pruebas Stripe sandbox; PayPal pendiente. Regalos y créditos requieren operador de servidor; consola global y descuentos de recompensas sobre suscripciones pagadas pendientes. [Propuesta](planes-costos-m13.md).

- **M14:** instalar adaptación Storage/SQL y actualizar app; configurar correo/WhatsApp reales. Asignar operadores reales a la consola global implementada con acceso autenticado/auditado, horarios, conservación y aviso de privacidad; notificaciones push/email y seguridad/limpieza de adjuntos pendientes. La IA prepara consultas revisables, sin analizar archivos automáticamente. Guía/producto y pagos se encuentran dentro de la app; campaña/sitio público externo sin publicar. [Alcance](m14-soporte-inicio-producto.md).

- **IA inicial/revisión:** ayuda incluida de temas públicos preparada con Gemini por defecto y alternativa GLM. Instalar `existing_starter_ai_review.sql`, desplegar `starter-ai` y configurar clave del operador, cuenta gratuita revisada y cupos. No envía expedientes ni texto libre. Ver [configuración](ia-incluida.md). Claves reales/servicio permanecen pendientes.
- **Acceso y experiencia:** recuperación de contraseña implementada localmente (correo/enlaces reales pendientes); reautenticación/eliminación de cuenta con conservación legal, nombres del equipo, aviso al salir implementado en RxEntryScreen, pacientes/eventos, plantillas/membrete/documentos y hospitalización (otros editores y recuperación cifrada pendientes), paginación y rutas web. La revisión completa prioriza estos faltantes sin presentarlos como implementados.

- **Respaldo protegido:** cifrado por contraseña y revisión de recuperación implementados; no restauran la base. Ver [alcance](respaldo-protegido-recuperacion.md). CSV continúa sin cifrar.
