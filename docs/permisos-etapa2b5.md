# Etapa 2B5 — revisiones hospitalarias por procedimiento (13E)

Estado: **candidato local para corte coordinado**, sin aplicar en Supabase, sin activar beta ni política de permisos y sin APK nuevo. Continúa el orden aprobado por la propietaria: permisos hospitalarios → medicación/frascos → consulta enfocada y servicios variables. No añade dosis, tablas clínicas, frecuencias, vías ni protocolos.

## Qué resuelve

Antes, `hospital_prescribe` admitía revisión o medicación como texto libre y comprobaba los puestos admin/MVZ. `hospital_task_action` conservaba controles de puesto y podía confirmar medicación antigua sin receta vinculada. El nuevo candidato separa programación de revisión, posposición y confirmación de realización usando permisos explícitos; ser admin/MVZ no los sustituye.

- `hospital_review_schedule`: exige `hospital.read` y `hospital.schedule` con habilitación profesional vigente. Recibe tipo de procedimiento activo de esa clínica, indicación y horarios explícitos. Mantiene validación de fechas futuras, ausencia de duplicados, máximo de entradas y reintento mediante recibo con huella del contenido. No se añade un horario clínico por defecto.
- La orden guarda `procedure_type_id` y `authority_grant_id`. Cada tarea audita autor, tipo y concesión que autorizó programarla. No exige historia completa, peso ni constantes.
- Confirmar una **revisión** exige `hospital.read`, `procedure.perform` para ese tipo exacto y habilitación vigente. La restricción profesional sigue el criterio conservador del piloto clínico 13C, no pretende ser una clasificación normativa de todos los cuidados de hospitalización. Un seguimiento no profesional requerirá un flujo explícito, no eliminar este control para cualquier tipo.
- Posponer exige `hospital.read` y `hospital.report`, motivo e intervalo explícitos; no marca la revisión realizada. Conserva los límites técnicos anteriores. Cancelar una indicación de revisión exige `hospital.read`, `hospital.schedule`, habilitación y motivo. Cancelar no significa registrar «no se aplicó» un medicamento; ese flujo estructurado sigue pendiente.
- La confirmación conserva usuario y hora real del servidor. Una segunda confirmación, incluso simultánea por la misma cuenta, recibe `task_already_confirmed`; no crea un segundo acto ni auditoría. Versiones obsoletas se rechazan. No se confirma antes de la hora prevista ni durante una posposición vigente.
- Se comprueba la autorización antes de devolver un recibo de reintento. Los cambios se serializan con el candado de clínica; habilitación y perfil usan el mismo candado de identidad que 13C. Se vuelve a comprobar vencimiento con hora real después de esperas, no solo con la hora inicial de la sentencia. El acceso a la nueva función se deniega a anon.

## Esquema concreto

`hospital_tasks.procedure_type_id`: UUID nullable, clave compuesta clínica/tipo a `private.procedure_types`. `authority_grant_id`: UUID nullable a la concesión de programación. Restricción de par: ambos presentes o ambos ausentes. Solo se escriben por las funciones de servidor; se conservan las denegaciones de escritura directa a clientes.

Las filas históricas quedan con ambos campos NULL. No se asigna un tipo por el texto de la tarea ni se transforma un puesto en permiso/habilitación. Se pueden leer con el permiso existente de hospitalización; confirmar una revisión antigua requiere un proceso de reautorización todavía pendiente. El candidato permite cancelarla con la autoridad explícita y motivo indicados, sin reescribir su origen.

La concesión guardada demuestra quién programó y con qué autoridad en ese momento. Revocar después el permiso del prescriptor no cancela automáticamente todas sus órdenes ya emitidas; desactivar o revisar órdenes es un acto distinto. Para realizar la tarea se comprueban siempre los permisos actuales del ejecutante y que el tipo siga activo.

## Rutas cerradas y límites del bloque

La ruta anterior `hospital_prescribe` se cierra: revisión exige la función con tipo; medicación exige orden estructurada. `hospital_task_action` rechaza medicación, incluso sin `prescription_item_id`, para no permitir la vía antigua de texto libre. La medicación estructurada utiliza las rutas de recetas/aplicaciones, cuya migración completa aún falta; este candidato **no afirma que esas rutas estén ya protegidas**.

Siguen pendientes `rx_schedule`, registro/validación de administración, `drug.administer`, `vial.draw`, frascos, alta hospitalaria (`hospital_discharge` conserva todavía su implementación antigua), y las demás rutas clínicas/documentales listadas en el corte. No habilitar el corte ni aplicar 13E por separado: otras funciones antiguas todavía pueden modificar tareas o registros.

También falta conectar en UI el selector de tipos, acciones por permiso, flujo de reautorización histórica y mensajes específicos de conflicto, y retirar los controles antiguos por puesto al completar la migración. La pantalla actual de órdenes no llama a `hospital_review_schedule`: **no presentar este bloque como un flujo disponible en el APK**. La próxima entrega de UI debe anunciar capacidad de servidor y fallar sin recuperar permisos anteriores si una instantánea conocida falla. No conceder un permiso general a todos los tipos para evitar seleccionar uno.

No modifica las referencias extraídas del portafolio ni importa sus valores en las calculadoras. No implementa aún cotizaciones, nuevos repartos o liquidación de comisiones.

## Pruebas

`bash supabase/tests/run_permission_hospital_reviews.sh` aplica las dependencias reales M2–M14 y candidatos 13A–13E en PostgreSQL Docker sin red, con cuentas/pacientes/evidencia exclusivamente sintéticos. No necesita secretos ni acceso a Supabase.

Casos: admin sin permiso; profesional verificado sin concesión; programación/reintento sin duplicar; vínculo de autoridad; tipo ausente; fechas inválidas; tipo incorrecto al realizar; permiso sin habilitación; revisión anticipada/pospuesta; motivo y versión; cancelación separada; registro de autor/hora/concesión; histórico sin conversión; cierre de texto libre y medicación; revocación antes de reintento; aislamiento entre clínicas y anon. La prueba entre sesiones verifica primera confirmación ganadora, rechazo tras revocación y vencimiento durante espera, y ausencia de escritura/auditoría duplicadas.

Resultado local: satisfactorio, incluida concurrencia entre sesiones. Evidencia CI: pendiente de registrar. No cambia Flutter en este bloque; no se repite su suite de 268 pruebas por una modificación exclusiva de SQL/pruebas/documentación.
