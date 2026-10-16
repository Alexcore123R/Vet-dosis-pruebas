# Etapa 2B7 — alta revisada y seguimiento de dosis (13G)

Estado: candidato SQL/UI para el corte coordinado; sin desplegar en Supabase, sin abrir beta y sin APK nuevo. No añade requisitos de anamnesis, peso, temperatura o jaula para guardar otros registros. No importa datos clínicos del portafolio ni inventa pautas.

## Estado en cuatro categorías

- **Implementado y probado previamente:** 13F de aplicaciones/frascos; 276 pruebas Flutter y seis trabajos de CI satisfactorios, como candidato.
- **Preparado local en esta entrega:** alta con revisión de pendientes, posposición de aviso y reporte de dosis no aplicada, integración de pantalla/versiones y pruebas.
- **Aplicado remoto y probado:** permanece la base previa de beta/permisos; esta entrega no cambia ese estado remoto.
- **Pendiente:** completar el resto del corte de permisos (recetas/delegaciones/reportes, agregados y auditoría, archivos/Storage/Edge, navegación completa e históricos), pruebas HTTP reales y alarmas en teléfono cerrado. No equivale a terminar toda la beta.

## Esquema y decisiones concretas

Dos códigos nuevos, sin concesiones automáticas:

- `hospital.discharge`: autorizar alta, requiere habilitación profesional vigente, además de `hospital.read`.
- `medication.followup`: por tipo de procedimiento, permite posponer el aviso o reportar que esa dosis no se aplicó. Requiere `hospital.read`; no habilita a administrar, extraer ni validar. Reportar una ausencia no afirma haber realizado un acto clínico: no exige por sí mismo habilitación profesional. No usa el puesto como autoridad.

`hospital_tasks.resolution_kind` es nullable, con `not_given` o `discharge`. Los históricos conservan NULL. La resolución usa el estado técnico `cancelled`, pero el significado se muestra por separado en UI. Restricción de integridad: una resolución tiene autor/hora/motivo, sin ejecutante, hora de aplicación ni registro de medicación. No se crean movimientos de producto por omitir o dar de alta.

Se conserva la bitácora existente: eventos con concesión, autor, hora de servidor, tarea/estancia y versiones. El identificador UUID de operación del seguimiento se guarda en los detalles de auditoría y en el recibo de idempotencia; no se confunde con el identificador numérico de la fila de bitácora. No se añade otra tabla paralela ni se reescriben eventos antiguos.

## Posponer y «No se aplicó»

`hospital_medication_followup` exige tarea estructurada de medicación con receta emitida, caso/paciente de la estancia, tipo y autoridad de programación. El permiso debe corresponder al tipo exacto, seguir vigente y pertenecer a la membresía actual. Tareas históricas sin estos vínculos no reciben autoridad automáticamente.

Motivo obligatorio en ambas acciones. Solo se reportan cuando llegó la hora prevista: no se usa esta función para cancelar anticipadamente un tratamiento futuro. Posponer conserva la fecha de la indicación y modifica solo el aviso; mantiene los límites técnicos existentes (1–30 minutos, hasta tres posposiciones). La pantalla no preselecciona el intervalo. Esto no define una frecuencia clínica ni mueve las dosis siguientes.

«No se aplicó» resuelve solo esa tarea, con motivo, autor y hora, sin crear aplicación, toma, validación o cobro. La siguiente dosis no cambia. La UI muestra «No se aplicó», nunca «Administrado». No significa autorización para cambiar toda la prescripción.

La primera resolución confirmada gana. Una aplicación previa impide declarar esa tarea no aplicada; una omisión o alta previa impide confirmar una aplicación vinculada después. La captura tardía de una aplicación real en una tarea cerrada requiere un flujo de revisión explícito pendiente; no se sobrescribe silenciosamente la resolución. Los reportes independientes de actos reales siguen el flujo 13F y no reabren tareas.

## Alta hospitalaria revisada

`hospital_discharge_preview` devuelve versión de estancia y todas sus indicaciones pendientes, incluidas las futuras, con una huella de su contenido/versiones. La pantalla muestra paciente, jaula (o sin asignar), indicaciones, motivo obligatorio y confirmación de revisión. No exige exploración completa ni mediciones no realizadas.

`hospital_discharge_confirm` vuelve a comprobar permisos/habilitación y bloquea estancia/tareas. Si cambió la estancia o cualquier pendiente, rechaza la confirmación: hay que actualizar y revisar otro resumen. No cancela tareas nuevas que la persona no revisó. Un reintento exacto autorizado no duplica el alta.

El alta cancela solo los pendientes de esa estancia y los etiqueta «Cancelada por alta». No cambia tareas ya aplicadas, dosis no aplicadas, volúmenes, conciliaciones, ventas o la receta emitida. Conserva motivo y auditoría de cada cancelación. El resumen activo deja de incluir la estancia dada de alta; no se añade aquí un archivo de altas en UI.

La ruta antigua `hospital_discharge` se cierra con `reviewed_discharge_required`; no mantiene una alternativa por rol. La compatibilidad antigua de la app solo se usa con servidores que todavía no anuncian el contrato nuevo. No desplegar este SQL con un APK que solo llame al endpoint antiguo.

## Confirmación de aplicaciones y concurrencia

Las aplicaciones de 13F vinculadas a tarea ahora exigen `hospital_task_version`. La versión se obtiene de `rx_hospital` y se envía desde el formulario estructurado cuando el contrato anuncia `task_versions`. El servidor comprueba estado y versión antes de escribir. Así, un formulario abierto antes de una posposición u omisión no registra otra aplicación con información desactualizada.

Se conserva la comprobación actual de permisos de aplicación/extracción y los recibos idempotentes de 13F. Un reintento de una aplicación ya registrada devuelve su resultado solo tras verificar la autoridad; no vuelve a descontar. Las correcciones siguen siendo anexas, no una confirmación nueva de tarea.

La clínica/libro, estancia, tareas y la autoridad profesional se serializan con las mismas herramientas de 13E/13F. Se vuelve a comprobar vencimiento tras esperas. Los endpoints nuevos deniegan anon y no conceden acceso entre clínicas. Las funciones privadas antiguas de snapshot quedan sin ejecución para clientes.

## Interfaz y avisos

El snapshot anuncia `medication_followup` y `reviewed_discharge`, permiso de alta y acciones por tarea. La entrada a «Registrar administración» se habilita solo con autorización clínica efectiva; abre el formulario de medicación, no el endpoint genérico de revisiones. La extracción se verifica cuando se elige un frasco.

Los formularios de seguimiento y alta muestran el contexto, exigen motivo/revisión, bloquean doble toque y conservan la clave para reintentar el mismo contenido. Cambiar el contenido invalida la revisión y cambia la clave cuando corresponde. Los campos vacíos no se rellenan con hallazgos normales.

Una actualización periódica con la misma versión de tarea permite continuar el formulario usando los permisos actuales. Una versión diferente o pérdida de permisos bloquea la acción; no se reutiliza el permiso antiguo del objeto retenido en pantalla. Los estados terminales quedan fuera de la planificación de avisos locales; eso no demuestra aún entrega de notificaciones con Android cerrado.

## Límites de la entrega

No se habilita beta ni se aplica 13G por separado. Faltan otras rutas de autorización: emisión de recetas y firma delegada, reportes, lectura de agregados/bitácora, Storage/Edge y navegación de puestos antes excluidos. Los históricos no se reautorizan por inferencia. No se implementan escalación remota, voz, alarmas de teléfono real ni seguimiento clínico automático.

La pantalla de alta no afirma que se hayan firmado consentimientos, entregado cuidados o cerrado cuentas: son actos separados. Tampoco se borran datos al dar de alta o vencer beta. Se conserva la decisión de retención acordada.

## Pruebas

`bash supabase/tests/run_permission_hospital_resolution.sh`: dependencias reales y candidatos 13A–13G en PostgreSQL 17 aislado sin red. Ejecuta primero el fixture sintético 13F, aplica 13G y prueba su comportamiento. No usa secretos ni expedientes reales.

Cubre tipo equivocado, puesto MVZ sin habilitación, seguimiento sin autoridad para aplicar, motivo/horario/versión, reintentos sin duplicación, omisión sin toma ni cambios a dosis siguientes, aplicación contra tarea resuelta, alta con revisión de futuras, cambio de pendientes y de estancia, cierre sin modificar aplicaciones/saldos, revocación de permiso, otra clínica y anon. Entre sesiones prueba omisión→aplicación, aplicación→omisión, alta→aplicación y rechazo de reintentos tras revocación/vencimiento durante espera.

Flutter: ocho pruebas nuevas de estado no aplicado sin alarmas, permisos actuales ante actualización, rutas separadas de aplicación/alta, revisión de hash, motivo/revisión/doble toque/reintento, posposición sin valor por defecto y alta con pendientes futuros y tarea resuelta mientras se abre el formulario. Las ocho pruebas nuevas y las 33 previas de hospitalización/medicación pasan en la suite completa.

SQL local y concurrencia: satisfactorios. Análisis sin observaciones. Suite completa Flutter: 284 pruebas satisfactorias. CI: [ejecución 38886746353](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38886746353), commit `8591fb3`; pasan los siete trabajos de permisos. El ajuste posterior de llaves de un `if` es únicamente de estilo y pasa análisis. Sin despliegue remoto ni APK nuevo.
