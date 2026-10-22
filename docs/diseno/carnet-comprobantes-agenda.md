# Carnet preventivo, comprobantes y agenda enlazada

Esta etapa completa el carnet preventivo dentro de Pacientes. Cada registro conserva su origen: aplicado en clínica, documentado externamente o informado por el tutor. La aplicación no convierte una vacuna triple o séxtuple en componentes automáticamente: el profesional selecciona manualmente las coberturas verificadas y puede añadir una descripción libre.

El carnet admite hasta tres comprobantes por registro (JPG, PNG o PDF, máximo 3 MiB cada uno). Se guardan de forma privada en la base de datos; la vista solo expone metadatos y el archivo se solicita explícitamente con permisos válidos. Los comprobantes no cambian el origen ni marcan por sí solos un registro como verificado.

También permite crear planes preventivos confirmados por un profesional verificado, retirarlos conservando el historial y enlazarlos con una cita de Agenda con hora y miembro elegidos. Una cita no modifica automáticamente la fecha del plan ni demuestra que la aplicación ya ocurrió. Los registros antiguos de próxima fecha se muestran como históricos pendientes de confirmar.

El PDF compartible es un resumen de revisión: incluye paciente, coberturas, fechas, origen, lote y planes activos. Excluye notas internas, autores, informantes, motivos administrativos, teléfonos, direcciones y archivos originales. No es una certificación clínica.

La migración es candidata y aditiva. Respeta las políticas existentes de eventos clínicos, permisos de lectura/escritura y revocación de profesionales; si la instalación no tiene el verificador profesional requerido, las acciones de confirmación permanecen deshabilitadas. El almacenamiento de archivos en `bytea` requiere incluir estas tablas en las copias de seguridad y definir retención antes de desplegarlo. La validación local y de CI no sustituye la prueba del selector de archivos, compartir/imprimir PDF ni permisos nativos en un Honor X6 con Android 14.
