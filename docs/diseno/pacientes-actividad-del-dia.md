# Pacientes: actividad y accesos por paciente

Implementado como continuación de Historia clínica/Carnet en el PR #7, sin despliegue remoto ni APK nuevo.

## Comportamiento

- Filtros Todos, Hospitalizados, En atención, En servicio y Pendientes de entrega; combinan búsqueda y especie. Contadores por paciente único dentro de los pacientes cargados y autorizados, no por número de episodios.
- Hospitalización incluye estancias activas de días anteriores, sin confundir ingreso con fecha del día.
- En atención usa citas consulta en estado en_atencion. En servicio usa estética en_atencion. Pendientes de entrega usa listo, sin inferir presencia física confirmada ni cobro pendiente.
- Agendado, entregado y cancelado no se presentan como actividad en curso. Los pendientes anteriores siguen visibles, identificados como tales; una cita sin paciente vinculado no se asocia por nombre.
- Las etiquetas muestran hora de ingreso hospitalario u hora programada de cita (no una hora real de inicio que aún no se registra). Se muestra responsable de cita cuando existe nombre disponible; hospitalización no inventa un responsable a partir del usuario que ingresó al paciente.
- La actividad tiene accesos a Hospitalización/Agenda con filtro por paciente, sujetos a la navegación y autorización actuales. No habilita acciones clínicas nuevas.
- La ficha abierta destaca alergias que ya estén disponibles con los permisos de lectura del expediente. No consulta alergias masivamente ni infiere ausencia si no hay entradas.
- La zona horaria y el día provienen del servidor y de la configuración de la clínica. Hay actualización manual y cada 30 segundos en primer plano. Al salir del primer plano, fallar una consulta o perder permisos se limpian estados; las respuestas anteriores no los restauran.

## Servidor

Nueva RPC de solo lectura patient_activity_snapshot, versión de contrato 1. Requiere patient.read explícito y separa hospital.read de appointment.read; no hay excepción por rol ni nuevas concesiones. Consulta columnas mínimas de estancias/citas, vinculando paciente y clínica. No devuelve tareas, diagnósticos, contactos, ventas ni expedientes completos.

La adaptación patient_activity_snapshot_v1.sql es nueva y requiere revisar el esquema remoto y la base de permisos antes de aplicar. No modificar/repetir los históricos 01–08. Si la RPC no está disponible se informa que no se pudo comprobar actividad, conservando el catálogo sin estados inventados. Esta entrega no afirma funcionamiento remoto.

## Pendientes que deben recordarse

- Servicios distintos de estética: faltan estados iniciada/finalizada en los actos de servicio; cobrar un servicio no demuestra que esté en curso.
- Consulta sin cita vinculada: un SOAP por sí solo no acredita una atención abierta; falta un ciclo explícito de inicio/cierre si se quiere cubrir ese caso.
- La hora real de inicio/finalización y la presencia/entrega física necesitan captura propia; los campos actuales son horarios de cita y estados declarados.
- Responsable clínico de estancia hospitalaria: no existe en el modelo actual. No sustituirlo por el autor administrativo del ingreso.
- El cambio no incorpora las observaciones futuras de Agenda de la usuaria; esa revisión queda después de Pacientes.

## Verificación

Pruebas de dominio, ciclo de vida, filtros combinados, texto al 200% a 320 px en claro/oscuro; análisis Flutter y suite completa. Fixture SQL sintético del endpoint: permisos separados, aislamiento, estancias anteriores, estados excluidos, fechas de clínica y revocación. No sustituye la prueba con la base real ni demuestra todo el corte RLS del sistema.
