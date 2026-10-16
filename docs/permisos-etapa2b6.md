# Etapa 2B6 — aplicaciones y frascos con permisos explícitos (13F)

Estado: candidato SQL/UI para el corte coordinado, sin aplicar en Supabase, sin abrir beta y sin APK nuevo. Continúa el bloque aprobado de hospitalización → medicación/frascos. No importa dosis, constantes, normas ni datos del portafolio; no verifica profesionales reales.

## Estado en las cuatro categorías

- **Implementado y probado anteriormente:** candidato 13E de revisiones; 272 pruebas Flutter y cinco trabajos SQL satisfactorios. No confundir candidato probado con versión instalada.
- **Preparado local en este bloque:** 13F, controles de interfaz y pruebas para aplicación, extracción, revisión profesional, gestión/consulta de frascos y programación tipada desde receta emitida.
- **Aplicado remoto y probado:** permanece la base anterior de beta/permisos, sin activar el corte. Esta entrega no modifica el proyecto remoto.
- **Pendiente del corte:** alta hospitalaria, posponer/no aplicación de medicación con flujo específico, reautorización de históricos, navegación completa por permisos, recetas/firmas/delegaciones/reportes, Storage/Edge y comprobaciones HTTP con dos cuentas reales. Los bloques de consulta enfocada, cotización/reparto/liquidación siguen después de los permisos.

## Autoridad y trazabilidad

Una aplicación nueva necesita lectura clínica y del paciente, habilitación vigente del responsable del caso, autorización personal de ese caso y `procedure.perform` para el tipo derivado del vínculo explícito de etapa/procedimiento de 13C. Además:

- `medication.report`: reportar el acto.
- `drug.administer` para ese tipo exacto: administrar el producto.
- `vial.draw` para ese mismo tipo, cuando se vincula un frasco: extraer volumen. Administrar no concede extracción.

Solo se reporta una aplicación propia; no se elige otro ejecutante en la UI nueva. El servidor comprueba la identidad aunque se manipule la solicitud. La concesión, autorización y vinculación deben existir en la hora observada; un permiso otorgado hoy no autoriza retroactivamente una captura anterior. También deben seguir vigentes ahora. Se validan fechas sin sustituirlas por la hora del teléfono.

La aplicación se conserva como **reportada, pendiente de validación**. `rx_medication_review` exige `medication.validate`, habilitación vigente y ser el responsable del caso y del registro; verifica el hash exacto, motivo y que el contenido no haya sido sustituido. No se valida automáticamente por ser quien aplicó, por puesto ni por coincidencia con una calculadora. Las incidencias conservan su bloqueo de validación hasta resolverse mediante corrección y revisión.

## Esquema concreto preparado para revisión del corte

Campos nuevos nullable en `medication_records`: `procedure_type_id` (clave de clínica/tipo), `scope_binding_id`, `report_grant_id`, `administer_grant_id`, `draw_grant_id` y `correction_grant_id`, con referencias a los registros inmutables correspondientes. Restricción: un registro con nueva autoridad tiene tipo, vínculo y concesiones de reporte/administración; la extracción se añade cuando corresponde. `controlled_drug_reviews.permission_grant_id` documenta la concesión de validación. Todos se escriben exclusivamente desde servidor.

Los registros históricos conservan NULL: no se adivina el procedimiento a partir del texto ni se inventa autoridad para validarlos. La UI no ofrece corrección/validación del histórico por el nuevo flujo hasta resolver su reautorización. Los movimientos antiguos, aplicaciones y revisiones no se reescriben.

Dos códigos nuevos de catálogo propuestos para este corte: `vial.read` (consulta de frascos/saldos) y `vial.manage` (apertura/conciliación; requiere habilitación). No se conceden automáticamente a admin/MVZ ni se derivan de `vial.draw`. Esta ampliación es parte del candidato, no una concesión remota aprobada a ninguna persona.

## Correcciones y saldo

La corrección exige `medication.validate`, responsable habilitado y motivo. Conserva producto, unidad, procedimiento, frasco, ejecutante y fecha observada originales; puede rectificar cantidad/vía. Una futura rectificación de identidad/fecha requiere un flujo explícito, no simular una segunda aplicación. La UI puede mostrar la versión de producto del registro aunque ya no sea la última del catálogo, sin completar concentraciones ausentes.

Se anexa otro registro, con quién corrigió y con qué concesión; no se sobrescribe el original. El delta del frasco es contable (cantidad anterior menos nueva), etiquetado expresamente como rectificación, **no devolución física**. No exige al corrector un permiso de administración/extracción como si él hubiera realizado otra toma; conserva las concesiones originales y añade la de corrección. La nueva versión queda pendiente de validación y el estado validado de una versión anterior no se hereda.

Abrir/conciliar frascos exige `vial.manage` y habilitación; se mantiene el responsable del frasco para cierre/ajustes. Consultar exige `vial.read`, con RLS para frascos/conciliaciones. Los movimientos vinculados a un caso se muestran solo con acceso clínico a ese caso; el permiso de frascos no abre todos los expedientes.

Los ajustes libres se deniegan si el producto es controlado, desconocido o no tiene clasificación vigente verificada. La verificación documental de productos es un flujo de servidor pendiente de revisión, nunca un selector para que el cliente se declare autorizado. Esta protección usa la clasificación versionada existente; **no implementa el catálogo global de controlados**, que sigue en la fase posterior acordada.

Se conservan volumen inicial, lote, apertura, movimientos y saldo exacto. Un reporte de un acto ya realizado con saldo insuficiente o frasco cerrado conserva la incidencia para revisión; no inventa volumen ni lo marca validado. Un cierre con discrepancia exige nota del MVZ y conserva esperado/medido/diferencia. No incluye autorización para corregir ventas o existencias con botones +/-.

## Hospitalización y concurrencia

`rx_schedule_typed` requiere receta emitida del responsable habilitado, lectura clínica/hospitalaria y `hospital.schedule`. Recibe etapa vinculada, fechas futuras explícitas, sin duplicados, y minutos de aviso elegidos. No preselecciona etapa ni intervalo clínico. Guarda tipo y concesión de programación en las tareas. La antigua `rx_schedule` se cierra, sin convertir llamadas antiguas en órdenes con autoridad nueva.

Confirmar una tarea con aplicación exige vínculo estructurado a receta/producto/caso, tipo y autoridad de programación; una tarea histórica sin estos vínculos requiere revisión, sin conversión automática. La programación no implica aplicación. Las revisiones de 13E siguen separadas.

Se serializan clínica, libro, caso e identidad profesional para las rutas modificadas; frasco/tarea se bloquean antes de escribir. La primera confirmación gana; una segunda recibe `task_already_confirmed` y no crea aplicación, auditoría ni descuento adicionales. Reintentar la misma operación con el mismo contenido devuelve el resultado solo después de comprobar nuevamente la autorización. La hora de reporte es del servidor y se conserva separada de la hora observada.

La pantalla de hospitalización de 13E todavía no anuncia la acción de medicación: el formulario estructurado está en Recetas/Medicación. Completar esa entrada, posponer y registrar «no se aplicó», revisión de alarmas y desbloqueo/confirmación en teléfono real sigue pendiente; este bloque no afirma que el recorrido clínico completo ya esté disponible en el APK.

## Contrato de interfaz y compatibilidad

`rx_operational_permissions` devuelve un contrato versionado y permisos de frascos, validación, programación y etapas con administración/extracción permitidas. La interfaz no usa una cédula capturada ni el puesto como sustituto. El formulario de aplicación no preselecciona etapa ni vía; permite un frasco solo con permiso de extracción de la etapa elegida. El servidor vuelve a comprobarlos al confirmar.

El contrato nuevo no abre las áreas aún no migradas. Sin `vial.read` no se pide la lista de frascos. Perder una respuesta conocida o recibir una versión de contrato desconocida borra facultades/datos y no recupera permisos antiguos. La compatibilidad de servidor anterior solo se acepta cuando la función nueva no existe y nunca se había conocido el contrato; errores de red o autorización no se interpretan como «servidor antiguo».

No se cambian aquí las facultades para preparar/emitir una receta: administrar no debe convertirse en permiso de prescripción. Esas rutas, `rx_profiles`, delegaciones, reportes y sus agregados conservan integración pendiente. No activar 13F de forma aislada ni afirmar que toda autorización de M6 esté migrada. SQL actualizado sin APK/contrato compatible rompería llamadas antiguas; el corte debe ser coordinado.

## Plan y riesgos restantes

1. Candidato de aplicaciones/frascos y su UI con pruebas aisladas; guardar evidencia de esta entrega.
2. Completar alta, acciones de medicación y reautorización histórica. Riesgo: confundir posponer/omitir con aplicación o atribuir permisos a órdenes antiguas.
3. Migrar recetas, identidad delegada, reportes y acceso a archivos/Edge. Riesgo: una ruta o agregado antiguo que permita saltarse permisos explícitos.
4. Corte revisado, pruebas HTTP reales y teléfono, antes de abrir beta. Sin dosis/normas importadas como verificadas por conveniencia.

## Validación de esta entrega

`bash supabase/tests/run_permission_medication.sh`: PostgreSQL 17 Docker sin red, dependencias reales M2–M14 y candidatos 13A–13F, sin credenciales ni conexión al servicio. Todos los profesionales, productos y cantidades son fixtures sintéticos; se prueban límites de permisos, no pautas clínicas.

Cubre separación reporte/administración/extracción/validación, tipo incorrecto, tiempo de concesión, identidad propia, frascos controlados/sin verificar sin ajustes libres, cierre con discrepancia, corrección inmutable con delta único y concesión, hashes/sustituciones, programación tipada/reintentos, doble confirmación de tarea, revocación, RLS, otra clínica y anon. Entre sesiones verifica una aplicación/toma única y rechazo tras revocación o vencimiento durante espera.

Flutter: cuatro pruebas nuevas de contrato explícito sin promoción por perfil/puesto, separación de facultades, limpieza ante error/pérdida de contrato y mensaje de confirmación duplicada; pasan junto con las ocho pruebas previas de recetas/medicación. Análisis sin observaciones. Suite completa Flutter: 276 pruebas satisfactorias. SQL local y concurrencia entre sesiones: satisfactorios. CI: pendiente de registrar.
