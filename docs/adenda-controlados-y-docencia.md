# Adenda: control farmacológico, frascos y personal en formación

Estado: fases de formatos y M6 implementadas y comprobadas localmente. Ver [alcance y límites actuales de M6](m6-recetas-control.md). La dispensación/POS ya está implementada localmente en [M8](m8-inventario-ventas.md); falta instalación y prueba real. No se modificó el proyecto Supabase remoto.

## Responsabilidad y autorización

Registrar una aplicación realizada no equivale a autorizar previamente ese procedimiento, validar el registro, prescribir o dispensar. Las autorizaciones de formación y los permisos de la app no sustituyen los requisitos normativos, que se conservan con fuente y estado de verificación.

El usuario confirmó que pasante equivale a auxiliar en esta app. Se conserva `auxiliar` como único rol; no se cambia la restricción de roles, las membresías ni el enum para añadir pasante. Personal en formación puede describirse en asignaciones y docencia, sin conceder permisos distintos.

Ser admin, dueño o disponer de una imagen de firma compartida no convierte al usuario en MVZ. Un admin que también ejerza como MVZ necesitará una habilitación profesional explícita de servidor, separada de la administración. Un perfil autodeclarado o una cédula escrita no conceden por sí solos esta habilitación. Solo un MVZ habilitado y responsable del caso podrá realizar los actos reservados descritos abajo.

| Acción | Auxiliar / pasante | MVZ responsable habilitado |
|---|---|---|
| Reportar una aplicación realizada | Sí: cantidad exacta, unidad, lote/frasco, paciente, procedimiento, quién aplicó y momento observado; siempre con hora de registro del servidor | Sí |
| Validar aplicaciones controladas | No, incluso con delegación permanente | Sí, con actor y hora de servidor |
| Corregir una aplicación controlada | Puede señalar una incidencia; no alterar el registro ni aprobar ajustes | Anexa corrección con motivo, preservando original |
| Preparar o emitir receta controlada | No; tampoco borradores, PDF con firma compartida o conversión desde receta ordinaria | Sí, cuando cumple los requisitos del tipo de receta |
| Generar y firmar reporte oficial de controlados | No | Sí; solo sus casos/registros bajo responsabilidad identificada |
| Dispensar producto que requiere receta cuantificada | No; el POS lo bloquea también en servidor | Solo MVZ habilitado, con receta y requisitos revisados |
| Preparar receta de producto no restringido | Solo con permiso específico del MVZ, caso y ámbito autorizados | Sí |
| Emitir/entregar receta ordinaria bajo delegación | Solo en los alcances permitidos y con MVZ responsable identificado; firma/identidad según autorización y normativa verificada | Sí |
| Proveer producto no restringido | Según permiso de dispensación separado y reglas del producto | Sí, sujeto a reglas del producto |

Para delegar receta/dispensación ordinaria, el producto debe tener clasificación y requisitos de receta conocidos y verificados que permitan ese flujo. «No es Grupo I» no significa por sí solo que no tenga restricciones. Una clasificación desconocida o un producto que requiera receta cuantificada bloquea este flujo delegado. La información de otros grupos y autoridades se verifica por producto; no inferir equivalencias automáticamente.

La regla de controlados prevalece sobre `professional_delegations`: ninguna delegación de nombre, cédula o firma permite saltársela. Si un borrador ordinario pasa a incluir un producto controlado/restringido, se bloquea para el auxiliar/pasante y requiere que el MVZ cree el documento correspondiente. No reutilizar el borrador como una receta controlada preparada por un usuario no autorizado.

## Reportado y validado son estados diferentes

Toda toma reportada afecta el saldo físico registrado aunque su aplicación esté pendiente de revisión. El registro conserva `performed_by`, momento de aplicación indicado, `reported_by` y `reported_at` del servidor. Si quien captura no es quien aplicó, ambos quedan identificados; no asignar automáticamente el acto al capturista.

Las decisiones de revisión se anexan en `controlled_drug_reviews`: entrada, MVZ responsable, decisión, motivo/corrección referenciada y `validated_at` del servidor. Estado visible inicial: «Reportada, pendiente de validación del MVZ». Validar no vuelve a descontar el frasco. El estado actual se obtiene de decisiones vigentes sin sobrescribir la aplicación original. La validación identifica un contenido exacto/hash y sus correcciones para no aprobar silenciosamente una versión diferente.

Una corrección sustantiva posterior produce un evento nuevo y requiere validación del contenido corregido. Si se transfieren responsabilidades, registrar el cambio explícito entre MVZ y conservar quién tenía el caso al aplicar/validar; no permitir que un admin se designe MVZ sin habilitación profesional.

## Nuevas tablas y relaciones propuestas

Se añaden a las tablas ya propuestas, sin rehacer pacientes, recetas, hospitalización, inventario ni lotes:

| Tabla | Contenido |
|---|---|
| `clinic_professional_authorizations` | Habilitación profesional de servidor vinculada a clínica/usuario, condición MVZ, estado, evidencia/referencia de revisión y vigencia. Separada del rol administrativo y de los permisos para compartir firma. No autohabilitable por el cliente. |
| `case_staff_assignments` | Paciente/caso/documento, cirujano, anestesista y MVZ responsable como asignaciones separadas, participantes y periodo. Cada acto registra su ejecutor real y conserva su asignación aplicable. |
| `person_procedure_authorizations` | Persona autorizada, clínica, procedimiento/tipo, alcance, MVZ otorgante responsable, contexto/caso si corresponde, supervisión requerida, inicio/fin y revocación. Visible en expediente según acceso al caso. No es autorización para emitir controlados. |
| `medication_vials` | Frasco/unidad identificada, clínica, producto/presentación y lote existentes, volumen inicial exacto/unidad, apertura registrada y estado. Saldo derivado de movimientos; no editable manualmente. |
| `medication_vial_movements` | Toma, merma, devolución físicamente verificada o ajuste: cantidad exacta/unidad, frasco, aplicación vinculada opcional, paciente, procedimiento, ejecutor/capturista, hora indicada y hora de servidor, motivo y vínculo a movimiento corregido. Solo anexado. |
| `medication_vial_reconciliations` | Saldo esperado, medición física reportada, discrepancia, motivo/nota del MVZ, decisión y hora de servidor. Una nota no elimina matemáticamente la discrepancia; el cierre conserva diferencia y estado conciliado o cerrado con discrepancia justificada. |
| `controlled_drug_reviews` | Revisión anexada: registro farmacológico/controlado y versión/hash revisado, MVZ, decisión, motivo y fecha de servidor. |
| `controlled_drug_reports` | MVZ responsable, periodo y alcance, estado completo/incompleto, corte del servidor, pendientes identificados y documento/PDF/hash inmutable. Rectificación mediante reporte nuevo vinculado, no reemplazo. |
| `controlled_drug_report_items` | Entradas validadas y decisiones exactas incluidas en el corte del reporte. Garantiza reproducción histórica aunque después haya correcciones. |

`medication_records` incorpora ejecutor/capturista separados, procedimiento, asignaciones del caso y relación con frasco/movimiento, además de lo ya propuesto. `professional_delegations` incorpora permisos independientes de receta ordinaria y dispensación ordinaria, con exclusión de controlados. `hospital_tasks` relaciona una confirmación con la aplicación y movimiento únicos; reintentos no generan otra toma.

Las nuevas relaciones verifican clínica en claves foráneas y RLS. El MVZ responsable debe pertenecer a esa clínica y tener habilitación vigente. El acceso de un pasante se limita a pacientes/casos asignados y a los actos autorizados; no incluye fichas sensibles de propietarios ni documentos ajenos.

## Frasco: saldo físico y correcciones

- Saldo exacto = volumen inicial + entradas/ajustes efectivos − tomas/mermas efectivas. Cálculo decimal exacto con una unidad coherente; no sumar mg y ml sin concentración/unidades verificadas. Las cantidades realmente utilizadas se capturan, no se sustituyen por la dosis calculada.
- La toma y su efecto sobre saldo se registran en una transacción con bloqueo del frasco y clave idempotente. Dos personas no pueden consumir simultáneamente el mismo saldo disponible ni descontar dos veces por reintento.
- Si una aplicación ya realizada supera el saldo registrado o usa un frasco cerrado, no ocultar el hecho: conservar un reporte de incidencia y bloquear nuevos usos/cierre hasta revisión. El MVZ concilia mediante movimiento anexado; nunca aumentar existencias silenciosamente para acomodar el reporte.
- Rectificar una captura errónea no significa devolver medicamento físicamente al frasco. La corrección identifica el dato rectificado y su efecto contable; una devolución real es otro evento explícito. Sin borrar tomas ni crear ajustes sin motivo.
- Mostrar junto a la toma la dosis calculada como referencia solo cuando existe resultado válido M3: peso fechado, dosis, concentración, unidades, presentación y versión/fuente. Si falta información, mostrar «referencia no disponible». Comparar referencia y cantidad real no demuestra automáticamente error clínico ni valida la aplicación.
- Al cerrar se solicita conciliación física. Si existe discrepancia, bloquear cierre ordinario. Solo el MVZ responsable puede cerrar con motivo y nota, conservando discrepancia y autorización. No presentar ese frasco como cuadrado. Una nota no dispensa requisitos oficiales de conservación/control.
- M8 integrará el frasco con su lote: descontar unidades de inventario al abrir/dispensar un envase y volumen al realizar tomas son movimientos distintos. Evitar descontar nuevamente un envase completo por cada aplicación.

## Reportes periódicos

Incluir únicamente entradas cuyo contenido efectivo esté validado por el MVZ responsable antes del corte. Filtrar pendientes dentro del mismo periodo y alcance; mostrar conteo/IDs y marcar «incompleto» si existen. No declarar completo un reporte que excluyó entradas pendientes o incidencias relevantes.

Solo el MVZ responsable prepara/genera/firma el reporte oficial. La exportación del auxiliar, si existe, será una consulta de trabajo claramente no oficial, sin firma ni formato oficial. La generación oficial también verifica vigencia de clasificación, fuente del formato y datos exigibles; si no están verificados, solo permitir salida de referencia sin alegar oficialidad.

Al validar después una entrada del periodo, el reporte emitido no cambia. Se genera una rectificación/complemento nuevo según reglas verificadas. El corte, alcance, lista exacta de entradas/revisiones, pendientes y hash del PDF quedan congelados.

## Consentimiento de docencia

Bloque opcional y editable por clínica con revisión del MVZ titular: describir que puede participar personal en formación, funciones previstas, supervisión, MVZ responsable y cómo se atenderán preguntas o preferencias del tutor. Registrar la versión y aceptación que correspondan al documento concreto.

No precargar una aceptación ni una autorización ilimitada para cualquier acto. La cláusula no concede credenciales profesionales, no reemplaza permisos por procedimiento y no anula revocación o responsabilidad profesional. Su redacción final pertenece a la clínica; no se presenta como cláusula legal verificada automáticamente.

## Pruebas adicionales requeridas

- Pasante/auxiliar reporta aplicación pero no valida, prepara/emite receta controlada, dispensa cuantificada o genera/firma reporte oficial, incluso con firma/delegación permanente.
- Admin sin habilitación profesional tampoco realiza los actos reservados. Otro MVZ de la clínica no valida un caso del que no es responsable.
- La toma pendiente descuenta una sola vez; validación/revalidación no descuenta; reintentos/concurrencia no duplican movimiento ni permiten saldo inconsistente sin incidencia.
- Corrección conserva original, motivo y autor; suma exacta del libro reproduce saldo y discrepancias. Cierre con discrepancia exige nota/decisión del MVZ y preserva la diferencia.
- Reporte contiene solo entradas validadas a su corte; pendientes lo marcan incompleto. Validar después no cambia PDF/hash/lista; rectificar genera otro reporte.
- Permiso ordinario revocado, clasificación desconocida o cambio a producto restringido bloquean el flujo delegado también por RPC/POS.
- Cirujano, anestesista, MVZ responsable, aplicador y validador permanecen distinguibles con sus fechas. No atribuir el acto a quien solo lo capturó.
- Firma/contenido de docencia congelados no cambian al editar la plantilla; cláusula sin aceptar no aparece como autorizada.
