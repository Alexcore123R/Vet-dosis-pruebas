# Permisos 2B-2: agenda y agregado de operaciones

Estado: candidato local posterior a 13A. No desplegado; no activa indicadores globales ni abre beta. No modifica términos, habilitaciones, tablas de dosis ni datos de pacientes existentes.

## Qué cambia

- `ops_write`, para crear, cambiar estado o reprogramar citas, exige `appointment.manage` explícito y vigente, antes de recuperar una respuesta idempotente. No basta el rol admin/MVZ/estilista ni estar asignado a la cita.
- El bloqueo de clínica y membresía conserva autoridad durante la operación y serializa con la administración de concesiones. Se comprueba vencimiento con reloj actual tras una espera. La auditoría registra la concesión usada y, al vincular un paciente, su concesión de lectura.
- `ops_patient_search` requiere `patient.read`; devuelve solo ID, nombre y especie, con el límite y búsqueda previos.
- Vincular un paciente a una nueva cita exige `patient.read` además de gestionar agenda. Se comprueba antes del recibo idempotente, de modo que revocar el acceso al expediente bloquea también el reintento.
- `ops_dashboard` exige membresía actual, expone citas solo con `appointment.read` y no deduce lectura del permiso de gestión. Sin `patient.read`, oculta el enlace `patient_id`; el nombre y especie capturados en la cita son datos de agenda, no acceso al expediente.
- Devuelve un mapa explícito de permisos y secciones disponibles. Para asignación de citas ofrece integrantes y nombres visibles, sin atribuirles títulos profesionales. Agendar a alguien no habilita a esa persona para ejercer un acto clínico.
- La interfaz deshabilita altas/cambios para un lector, no abre expedientes sin permiso y no muestra controles de secciones indisponibles. Si ya recibió el contrato de permisos explícitos y la consulta falla o el servidor omite ese contrato, limpia datos y no recupera el comportamiento de roles antiguos.

Se conserva la validación de estados, motivo de cancelación/reprogramación, control de versión, duración de cita, detección de solapamientos e idempotencia. Se rechaza también una modificación sin versión explícita. La cuota de almacenamiento continúa protegida por los triggers de planes existentes.

## Agregados y límites deliberados del candidato

`ops_dashboard` antes agregaba precios, comisiones, servicios, tareas, mensajes y proveedores desde una función con privilegios. Los permisos de agenda no autorizan esos datos. Este candidato devuelve esas secciones vacías y no disponibles hasta integrar por separado sus facultades. Ni `workspace.manage` ni el rol antiguo se toman como atajo financiero o clínico.

Esto aún no es un dashboard completo bajo permisos nuevos. Las consultas independientes de estadísticas, inventario, hospitalización y asistencia (`att_dashboard`) siguen pendientes de su propio corte. Los RPC de escritura no relacionados con agenda conservan su implementación previa: no se presentan como migrados. El acceso directo cliente a tablas operativas continúa revocado, como antes.

El wrapper exterior de planes de `ops_write` se conserva: las funciones de equipo siguen exigiendo el plan correspondiente. La rama nueva de agenda nunca usa autorizaciones antiguas. `ops_write_before_plans` permanece sin EXECUTE para clientes, por lo que su rama histórica de agenda no es una ruta alternativa accesible. La función nueva de escritura es privada y tampoco tiene EXECUTE para clientes.

La asignación en agenda se trata como acto administrativo: se elige un integrante vigente de la misma clínica. No se usa el puesto para acreditar habilitación. Los permisos para realizar el procedimiento se comprobarán en la operación clínica correspondiente, no al reservar un horario.

## Despliegue y compatibilidad

La migración candidata `13B_permission_agenda.sql` requiere planes/extensión de agenda, base de permisos y beta cerrada. Cambiaría inmediatamente estos RPC aunque el indicador global de permisos siga apagado: no desplegarla sola. Debe incorporarse al corte coordinado con 13A, el resto de áreas y las pruebas Auth reales.

La app conserva compatibilidad con el contrato anterior mientras el servidor remoto no esté migrado. Tras recibir el mapa de permisos nuevos, no lo sustituye por un rol antiguo si hay errores o falta el mapa. Esta compatibilidad de presentación no concede autoridad al cliente ni añade un OR de roles a la evaluación nueva del servidor.

No se incluyen pacientes reales ni profesionales verificados de ejemplo. No se publica un APK en este paso.

## Pruebas

`bash supabase/tests/run_permission_agenda.sh`

Reconstruye las adaptaciones reales hasta M13/M14, equipo y extensión de agenda, con planes, cuotas y wrappers. Añade base beta/permisos, 13A y 13B. Solo datos sintéticos en PostgreSQL Docker sin red.

Cubre: rol admin sin concesión; gestión sin lectura; lectura sin gestión aunque la persona esté asignada; enlace de expediente separado; buscador y enlaces ocultos sin permiso; datos de áreas ajenas ausentes aun existiendo filas; aislamiento entre clínicas; anon; falta de acceso a tablas y wrapper histórico; motivo y versión de reprogramación; auditoría; revocación ante reintento; revocación que gana el bloqueo y vencimiento durante espera. No acredita acceso a otros RPC pendientes.

Pruebas Flutter: lector con rol admin no agenda/modifica ni abre expediente; sección no disponible no muestra acciones antiguas; error o respuesta sin mapa de permisos tras recibirlo limpia datos sin recuperar privilegios. Incluye regresión de captura y dashboard.

Resultado local SQL y concurrencia: satisfactorio. Registrar comprobación completa de Flutter y GitHub al terminar. No equivale a pruebas contra el Supabase remoto.
