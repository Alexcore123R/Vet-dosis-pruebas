# M5 — Hospitalización

Módulo Flutter con ViewModel, repositorio Supabase y planificador de avisos aislado de la UI. Entrada desde Hospitalización en Home. No necesita un catálogo farmacológico precargado: registra indicaciones proporcionadas por MVZ/admin, sin generar dosis ni protocolos.

## Hoja y permisos

- Ingreso de paciente existente de la misma clínica y etiqueta de jaula/box. Una jaula con la misma etiqueta (ignorando mayúsculas y espacios externos) admite un solo ingreso activo; un paciente no puede tener dos ingresos activos en su clínica.
- Fichas por jaula y tabla paciente × hora, desplazable horizontalmente en celular. La celda conserva los minutos reales de cada tarea y permite varios tratamientos en la misma hora. Selector de fecha, alertas de retraso y resumen de pendientes con horario cumplido.
- MVZ/admin captura medicación o revisión, indicación textual y horarios explícitos. La revisión de paciente, indicación y horarios es obligatoria. No se asignan fármacos, cantidades ni intervalos automáticamente.
- Los nuevos horarios deben estar en el futuro y no repetirse. Se envían como instantes UTC; los selectores y la hoja muestran la zona local del dispositivo. Revisar la zona del teléfono antes de programar tratamientos.
- Admin/MVZ prescribe, ingresa, cancela y da alta. Auxiliar consulta y registra realizaciones/posposiciones. Recepción/estilista no leen hospitalizaciones. RLS y RPCs imponen los permisos; no hay edición directa de las tablas desde el cliente.
- Registrar una administración/revisión exige revisar la ficha y confirmar que ya se realizó. La hora registrada es la de confirmación del servidor, no una hora retrospectiva indicada por el usuario. El servidor rechaza confirmaciones anteriores al horario indicado.
- Primera confirmación: usuario autenticado y `now()` del servidor. Reintento del mismo usuario no altera actor/hora ni duplica la bitácora. Un segundo usuario no puede volver a marcarla. Las versiones detectan cambios entre apertura del diálogo y envío.
- Posponer solo mueve el aviso; conserva el horario clínico original y el estado pendiente. Motivo obligatorio, 1–30 minutos, máximo tres posposiciones por tarea. La UI ofrece 5/10/15/30. Son límites técnicos del aviso, no recomendaciones médicas.
- Aviso de retraso configurable por el prescriptor (1–120 minutos). El retraso clínico continúa visible aunque el sonido esté pospuesto. Escalamiento local = prioridad visual y segunda notificación local; no contacta automáticamente a un supervisor.
- Alta con motivo cancela atómicamente todos los pendientes y libera la jaula, conservando registros realizados y datos históricos. Las tablas mantienen la historia, aunque la pantalla inicial muestra ingresos activos. Consultar altas, cambiar de jaula y vincular el historial con M4 son iteraciones posteriores.

## Avisos por plataforma

### Android / iPhone

`flutter_local_notifications` estable 21.0.0 y `timezone`. Solo se solicitan permisos al pulsar **Activar / revisar permisos de avisos**.

Android: icono específico, permiso de notificaciones y `SCHEDULE_EXACT_ALARM`, desugaring Java y receptores de programación/reinicio configurados. Con permiso de alarma exacta se usa `exactAllowWhileIdle`; de otro modo se usa programación aproximada y la UI indica que puede retrasarse. No se solicita evitar No molestar ni acceso a alarmas de pantalla completa.

iPhone: permisos de alerta/sonido a petición y delegado de notificaciones configurado. El sistema entrega notificaciones locales programadas incluso con la app cerrada normalmente; sonido, Focus/No molestar, silencio, ahorro de batería, cierre forzado y permisos limitan la entrega. No se garantiza un sonido en el segundo exacto ni una alarma continua hasta confirmar.

Programación: aviso de horario y aviso de retraso, reemplazados/cancelados al actualizar desde el estado del servidor. Tareas atrasadas se agrupan en un recordatorio genérico, deduplicado entre actualizaciones, para evitar muchas alertas simultáneas. Posposición respeta el instante nuevo del aviso.

Máximo 60 avisos próximos por dispositivo y clínica activa, dejando margen respecto al límite de 64 notificaciones pendientes de iOS. Si el plan excede esa capacidad, aparece un mensaje explícito; abrir/actualizar la hoja programa los siguientes. Esta versión no garantiza cubrir todos los horarios de una hospitalización muy grande sin actualizar la hoja. El presupuesto deberá compartirse con avisos de agenda en módulos posteriores.

No se muestran nombres de pacientes, contactos, medicamentos o indicaciones en pantalla bloqueada. El aviso dice que se abra la app y se compruebe el estado actual **antes de administrar**. No ofrece botones para administrar directamente desde la notificación. Pulsarlo abre Hospitalización pasando por el acceso de sesión y rol.

La app cerrada no consulta Supabase: otro miembro puede haber confirmado o cancelado una tarea sin que este dispositivo lo sepa. Puede aparecer un aviso local pendiente hasta volver a sincronizar. La notificación no demuestra que falte una dosis ni autoriza repetirla. Cancelación remota en segundo plano requerirá integración de push/backend adicional.

### Web / computadora por navegador

Avisos visuales y resumen de retrasos mientras la hoja está abierta, actualizados cada 30 segundos. El navegador puede ralentizar pestañas en segundo plano. **Cerrar el navegador detiene esos avisos**. No se promete alarmas programadas con navegador cerrado; requeriría otra infraestructura de push/service worker y soporte compatible.

## Datos, sesiones e idempotencia

`supabase/adaptations/existing_hospital_m5.sql`: aplicar una vez después de M2 y M4. Crea `hospital_stays` y `hospital_tasks`, restricciones, RLS, RPCs y auditoría. Reutiliza los comprobantes privados de operación de M4 para reintentos de ingreso/prescripción sin duplicación. Los RPCs de transición bloquean ingreso y tarea en el mismo orden, evitando doble confirmación concurrente y carreras con altas.

La migración está preparada y probada localmente; **no se ha aplicado al Supabase del usuario**. No se han creado registros reales. M3 es independiente y sus datos clínicos siguen pendientes.

La hoja requiere conexión para consultar o registrar. Datos clínicos solo en memoria, sin agregarlos a la caché sin cifrar o a la cola offline. El dispositivo persiste metadatos de avisos: identificadores de usuario/clínica/tarea, identificadores numéricos de notificación y huellas temporales de programación; no guarda nombres, contactos, fármacos ni indicaciones en esas preferencias. El propio sistema operativo guarda las notificaciones genéricas programadas.

Cambiar de sesión, clínica activa o rol cancela los avisos de hospitalización anteriores. Cerrar un formulario por cambio de identidad elimina su contenido, usando la protección de navegación de M4. Un fallo de lectura limpia la hoja en memoria y muestra el error; los avisos ya programados pueden mantenerse como recordatorios genéricos del último estado conocido.

## Verificación

- Pruebas Dart de estados, extremos de tiempo, UTC, repetición de horarios, posposición, escalamiento, capacidad, deduplicación, cancelación al confirmar y cambios de sesión durante programación.
- Pruebas de permisos del ViewModel, lecturas tardías/fallidas y tabla móvil sin desbordamiento vertical. Backend nativo simulado: no se prueba sonido real con estas pruebas.
- `bash supabase/tests/run.sh hospital`: PostgreSQL 17 aislado, permisos, clínicas, ocupación de jaula, reintentos, horarios futuros, versiones, actor/hora del servidor, límite de posposición y alta conservando administraciones.
- Dos conexiones concurrentes reales a PostgreSQL local: una confirmación se acepta y la otra queda bloqueada; hay un solo registro de administración en bitácora.
- Análisis y compilación web configurada.

Pendiente al final: aplicar migraciones remotas y probar cuentas, compilar Android/iOS, comprobar sonido, permisos, app cerrada, reinicio, batería, Focus y límites de capacidad en dispositivos reales. La configuración nativa está escrita, no certificada como operativa en teléfonos aún.
