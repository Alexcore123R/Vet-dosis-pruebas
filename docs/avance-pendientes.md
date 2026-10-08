# Implementación de pendientes

## Bloque 1: acceso y protección de captura (8 de octubre de 2026)

Implementado localmente:
- Solicitud de recuperación de contraseña por correo, con respuesta neutral que no confirma si una cuenta existe.
- Supabase procesa el enlace de recuperación; la app muestra nueva contraseña y confirmación, y exige una sesión de recuperación para actualizarla. Cancelar cierra sesión. Las membresías y roles no cambian.
- Aviso al retroceder desde `RxEntryScreen` con cambios: seguir editando o salir sin guardar. Cubre los formularios que reutilizan este componente, incluyendo sus indicaciones y firmas; no todos los editores de la app.
- Durante el envío se bloquea retroceder. Un fallo conserva la captura; un guardado exitoso permite cerrar sin aviso.

No se guarda un borrador clínico sin cifrar en el dispositivo. El aviso protege la navegación dentro de la app; no puede impedir que el sistema cierre el proceso o que el usuario cierre la pestaña. Recuperar borradores y extender el aviso a los demás editores siguen pendientes.

### Integración final

En Supabase Auth, configurar URL del sitio, redirecciones web y `com.vetdosis.pro://login-callback/`, correo transaccional y límites de envío. Probar enlaces reales, expiración, reuso, correo y recepción de enlaces en cada plataforma. No se envió correo real durante estas pruebas. La configuración y las verificaciones del proveedor se harán al final; solicitar una clave o configuración adicional ahora no es necesario.

## Siguientes bloques de código

1. Extender protección de captura a los editores clínicos y de documentos, con revisión de privacidad para recuperación de borradores.
2. Gestión del equipo e invitaciones: listado, revocación y cambios de rol con controles del servidor y protección del último administrador.
3. Identidades legibles del equipo y vinculación de citas a pacientes.
4. Flujos pendientes de inventario, devoluciones y frascos, conservando movimientos y correcciones anexadas.
5. Restauración verificable de respaldos y mejoras de navegación, paginación y accesibilidad.
6. Ciclo de suscripciones y soporte: cancelaciones, impagos, adjuntos y retención, antes de activar cobros.

Cada bloque debe registrar alcance real y pruebas. Esta lista no afirma que los bloques restantes estén implementados.

## Información y servicios que se completan al final

- Catálogos clínicos con fuentes y revisión profesional; clasificación normativa y textos/aviso de privacidad aprobados por la clínica.
- Credenciales y cuentas elegidas de IA, pagos, Google/Drive y proveedores opcionales de mensajería.
- Configuración de producción, dominio, cuentas de publicación, identidad visual y pruebas con teléfonos reales.
- Validación de costos y condiciones comerciales.

El código preparatorio y sus pruebas locales pueden avanzar antes de estos aportes. Algunas comprobaciones finales requieren también nuestro trabajo de despliegue y pruebas, además de los datos que aporte la usuaria.

## Verificación del bloque 1

`flutter analyze`: sin incidencias. `flutter test`: 138 pruebas aprobadas, incluyendo recuperación con sesión válida/confirmación y conservar o descartar cambios al retroceder. No se cambiaron tablas ni se aplicaron migraciones remotas en este bloque.

## Bloque 2: equipo e invitaciones

Implementado localmente para el esquema Supabase existente:
- En «Mi cuenta y clínicas», el administrador conectado de una clínica puede abrir «Administrar equipo e invitaciones».
- Lista de integrantes identificados por correo, cambio de rol y baja con confirmación. La baja elimina la membresía, no la cuenta ni sus registros históricos.
- Invitaciones con estado pendiente, aceptada, revocada o vencida; revocación de pendientes mediante el RPC existente. Los códigos secretos y hashes no se devuelven en el listado.
- El servidor autoriza cada operación por clínica y administrador; conserva la protección existente del último administrador y registra las bajas en la bitácora. La UI refresca las membresías después de cambios.
- Ante un fallo de lectura se borra el listado. Si cambian los permisos, deja de mostrarse el contenido de administración. La consulta no muestra fichas médicas del personal.
- Un rol de acceso no habilita automáticamente a un profesional para actos clínicos reservados.

Integración final: aplicar `supabase/adaptations/existing_team_management.sql` una vez, después de M2 y antes de utilizar esta pantalla. Es aditivo: dos RPC nuevos, sin tablas nuevas ni reemplazo del esquema. La modalidad de instalación nueva aún no expone esta pantalla; se trabaja sobre la base existente aportada por la usuaria. No se modificó la base remota.

Verificación: 140 pruebas Flutter aprobadas; pruebas SQL locales de M2 y equipo aprobadas (permisos, último administrador, baja y bitácora). Pruebas enfocadas de pantalla y autenticación aprobadas tras el ajuste de disponibilidad para el esquema existente. Los nombres legibles en otras pantallas y el listado paginado de equipos muy grandes continúan pendientes.

## Bloque 3: agenda, nombres visibles e historial al dar de baja

Implementado localmente:
- Búsqueda de pacientes por nombre dentro de la clínica (máximo 50 coincidencias por búsqueda). El selector solo recibe ID, nombre y especie; no recibe propietarios ni notas clínicas. Un resultado tardío se descarta si cambia la búsqueda.
- Cita vinculada a un paciente existente. El servidor toma el nombre/especie del expediente; no confía en los valores enviados desde el dispositivo. Mantiene la opción de cita sin expediente, sin crear un paciente automáticamente. El estilista continúa sin acceder al buscador de expedientes.
- Al pulsar una cita vinculada, se abre el paciente con los permisos actuales del usuario. No concede acceso clínico a recepción.
- Reprogramación de citas agendadas, validación de solapamientos y versión del registro. Cancelaciones y reprogramaciones exigen motivo; la bitácora conserva horarios anteriores, autor y fecha del servidor. Los reintentos de la misma operación no duplican cambios.
- Nombre visible propio por clínica, editable desde Agenda. Se usa en asignaciones, pendientes, mensajes, desempeño y checado; exportaciones de servicios/asistencia conservan el ID y añaden el nombre. No se reutiliza la cédula ni la firma profesional. El nombre visible es autodeclarado, no una acreditación de identidad.
- Los nombres se incluyen en el respaldo operacional. No cambia el alcance de exportación de chats privados.
- Corrección de bajas: agenda, tareas, servicios y asistencia referencian la identidad de la cuenta y clínica para conservar el historial, sin exigir una membresía activa. Cada nueva asignación/acto sigue verificando una membresía activa. La ficha médica consentida se conserva bajo sus controles de acceso; su conservación y eventual eliminación se deben definir antes de operación real.

Ampliación de captura protegida:
- Nuevo paciente, eventos clínicos, editor de plantillas, membrete/logo, editor de documentos y formularios de ingreso/indicaciones de hospitalización avisan antes de salir con cambios pendientes.
- Bloquean retroceder mientras guardan; el éxito permite cerrar y el fallo conserva la captura.
- No guardan borradores clínicos sin cifrar en el dispositivo. El cierre de proceso o pestaña aún puede perder cambios no guardados. Los editores que no usan estos componentes y la recuperación cifrada de borradores siguen pendientes.

### Instalación final

Después de las adaptaciones existentes M2–M14 y `existing_team_management.sql`, aplicar una vez, en este orden:
1. `supabase/adaptations/existing_appointments_extension.sql`: añade nombres visibles y búsqueda; actualiza agenda, vistas y exportación, preservando la envoltura de permisos de planes.
2. `supabase/adaptations/existing_membership_history.sql`: ajusta relaciones históricas y mantiene la comprobación de membresía en nuevas capturas.

Antes de aplicarlas en producción, respaldar y revisar cualquier `patient_id` previo que no corresponda a la clínica: la nueva clave foránea rechazará ese dato. No reescribe ni elimina registros para forzar la instalación. Estas adaptaciones se probaron en PostgreSQL aislado; no se ejecutaron sobre la base remota.

### Verificación

145 pruebas Flutter aprobadas; 15 comprobaciones enfocadas adicionales pasaron tras mejorar las exportaciones. Análisis sin incidencias y compilación web de producción completada. SQL local de agenda, historial, planes, IA y soporte aprobado: paciente de otra clínica rechazado, identidad tomada del expediente, solapamiento y versión comprobados, motivos obligatorios, reprogramación idempotente y baja que conserva servicios/asistencia/ficha consentida. Pruebas de pantalla comprueban selección, descarte de búsquedas tardías, cambios sin guardar y bloqueo durante envío.

Pendientes de código que siguen abiertos: paginación general, nombres en otras áreas clínicas, restauración y cifrado de respaldos/borradores, adaptadores offline por módulo, incidencias de frascos cerrados, devoluciones parciales y anticipos/pagos divididos, ciclo completo de suscripciones, limpieza de adjuntos y navegación web. Los bloques 1–3 no equivalen a completar toda esta lista.

## Bloque 4: cifrado y revisión de respaldos

Implementado: exportación cifrada con contraseña por defecto, apertura de archivos protegidos, comprobaciones de integridad más estrictas y resumen para revisar una recuperación. La contraseña no se guarda ni se envía al servidor. Se conservan los bytes originales del archivo y las cantidades textuales del snapshot. CSV y la opción explícita JSON siguen sin cifrar.

La revisión exige la clínica correcta y rechaza archivos alterados, rutas de fotos fuera de alcance y registros mezclados. Muestra cantidades de registros y permite exportar un informe; no ejecuta una restauración. El archivo operacional no incluye todo lo necesario para reconstruir el servidor.

Verificación: 148 pruebas generales aprobadas, más el caso criptográfico completo ejecutado por separado y una comprobación nueva de pantalla/permisos; 150 casos distintos aprobados en total. Tras los ajustes de pantalla pasaron las cuatro pruebas enfocadas de respaldo sin repetir el caso criptográfico. Análisis sin incidencias. Compilación web de producción completada.

[Detalle, uso, límites y restauración pendiente](respaldo-protegido-recuperacion.md). No se crearon tablas ni se modificó el proyecto remoto. Drive, recuperación completa del servidor, exportación por lotes y cifrado de borradores/caché clínica continúan pendientes.
