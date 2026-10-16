# Recetas y autorizaciones: propuesta de integración 13H

16-oct-2026. Revisión del código actual; atribución aprobada por la usuaria e integración por etapas. No es una migración aplicada ni habilita la beta. Complementa el esquema beta-permisos v1.1; no sustituye la revisión normativa.

## Estado comprobado

| Categoría | Evidencia / alcance |
|---|---|
| Implementado y probado | M6 contiene borradores, versiones de perfil, delegaciones revocables, snapshot, PDF con hash y emisión. Esto no demuestra que ya use el nuevo modelo de permisos. El conjunto local hasta 13G tiene 284 pruebas Flutter y análisis limpio; siete trabajos satisfactorios en el run 38886746353. |
| Preparado local | Candidatos 13A–13G, todavía sin despliegue coordinado. 13H1 añade registro de firma propia ligado al borrador y contrato PDF de atribución. Es un bloque parcial: las rutas actuales de preparar/emitir todavía no lo consumen. No existe todavía un corte integral 13H. |
| Aplicado en remoto y probado | La base de permisos 11A está desplegada con el corte desactivado, según la evidencia anterior de 2A. No se ha ejecutado una comprobación remota nueva en esta revisión. No atribuirle las pruebas locales de 13G. |
| Pendiente | Separar preparación de autorización; reemplazar autoridad heredada; trazabilidad de autorización individual/permanente; UI y conexión del PDF con preparación/emisión; revocación concurrente del flujo completo; políticas y RPC; pruebas HTTP/Edge reales. |

## Hallazgos del recorrido actual

Fuentes: `supabase/adaptations/existing_prescribing_m6.sql`, `lib/modules/prescribing/presentation/prescribing_screen.dart` y `prescribing_view_model.dart`. Son hallazgos de código, no afirmaciones de explotación en el servidor.

1. `private.rx_professional` usa puesto admin/MVZ y `clinic_professional_authorizations`. No consulta por sí mismo la verificación profesional nueva. Es un helper compartido con formatos y reportes: reemplazarlo globalmente sin revisar consumidores ampliaría el cambio fuera de recetas.
2. `rx_prepare` llama a `private.rx_emit_check`, que exige `rx_permission(...,'issue')`. Por tanto, preparar el PDF y autorizar su emisión todavía están acoplados.
3. Preparar exige un perfil propio del actor incluso al usar datos del responsable. El preparador debe poder identificarse como miembro sin declarar una cédula ni convertirse en profesional.
4. `rx_prepare` puede escoger un perfil profesional distinto del responsable del caso. El nuevo contrato debe vincular los datos profesionales al responsable aceptado, sin permitir que otro perfil compartido sustituya esa responsabilidad.
5. El snapshot guarda perfil/emisor y referencias, pero la receta no tiene un registro explícito suficiente del preparador final, el autorizador, la modalidad y la concesión usada. `created_by` no equivale necesariamente a quien preparó la versión emitida.
6. La interfaz ofrece compartir firma, emitir y dispensar como casillas de una delegación. No basta con renombrarlas: la dispensación sujeta a receta exige habilitación y permiso propios; la autorización permanente no presta esa facultad.
7. El PDF dice «firma propia de quien emite» o «firma del titular compartida», sin distinguir revisión individual de autorización previa. La confirmación de pantalla usa el mismo texto para ambas situaciones.
8. `rx_finalize` puede devolver una receta ya emitida antes de revalidar la autorización de emisión. La repetición debe comprobar el acceso vigente y la identidad del acto antes de devolver el recibo, sin volver a emitir ni modificar el PDF histórico.

## Flujo propuesto

### Preparación

Miembro con `patient.read`, `clinical.read` y `prescription.prepare` crea/edita el borrador del caso accesible. No requiere habilitación por el mero acto de transcribir. El responsable debe estar definido y haber aceptado la responsabilidad; no se asigna por puesto ni por seleccionar un perfil.

Preparar genera una versión para revisión, con preparador y hora del servidor. No emite, no aplica, no dispensa y no usa automáticamente una firma profesional. Los campos clínicos existentes siguen siendo explícitos: no añadir vía, frecuencia o primera dosis predeterminadas.

### Autorización individual

El responsable habilitado, con `prescription.authorize`, revisa la versión exacta. El acto de autorización queda ligado al contenido, preparador y versión del perfil. La indicación de revisión individual solo aparece cuando ese acto realmente ocurrió. La firma obligatoria de quien realizó la consulta se identifica por separado; no se sustituye por la del responsable. El servidor congela el PDF autorizado; la confirmación final corresponde a su hash exacto.

Si cambia cualquier dato después de la autorización, la versión anterior deja de habilitar la emisión. No autorizar un PDF desde su hash suministrado por el cliente sin comprobar el contenido del servidor.

### Autorización permanente ordinaria

Se reutilizan `professional_delegations` y sus revocaciones, añadiendo metadatos; no se crea una segunda tabla de delegaciones paralela. Solo el titular habilitado con `prescription.authorize` puede concederla explícitamente, con destinatario, tipo de documento, alcance y vencimiento.

El preparador sigue necesitando `prescription.prepare`. La autorización permanente referencia la concesión del titular, no otorga `prescription.authorize` ni habilitación al preparador. Se reevalúan ambas partes al preparar el documento final y al emitirlo.

Propuesta para el primer corte: autorización por **caso y tipo `ordinary_prescription`**, conservando la restricción actual de caso para facultades de receta. Ampliarla a todos los casos de la clínica cambia el alcance de seguridad y necesita decisión explícita; no inferirlo de `case_id NULL` heredado.

El PDF indicaría: «Preparada por [persona] el [fecha]. Emitida por [persona] bajo autorización previa de [MVZ], otorgada el [fecha], vigente hasta [fecha], para [alcance]. No consta revisión individual de este documento». No afirmar que el MVZ revisó o firmó personalmente esa receta.

Propuesta para el primer corte: **no estampar automáticamente la imagen de firma del titular** en recetas emitidas por autorización permanente. Conservar la evidencia de la autorización previa en servidor y mostrar su referencia. La usuaria aprobó separar estos datos y firmas; no se presenta como conclusión legal sobre la validez de una receta sin firma individual.

### Nombre y firma de quien realizó la consulta: decisión aprobada

La usuaria confirmó y autorizó:

- Rótulo **«Consulta realizada por: [nombre]»**, con nombre y firma propia obligatorios al emitir. La firma identifica a quien debe rendir cuentas al responsable; no concede habilitación ni facultad de prescribir.
- Si otra persona captura, **«Documento elaborado por: [nombre]»** separado. Si es la misma persona, no repetir ese rótulo.
- Puesto/función no se imprime por defecto; puede ser configurable cuando el formato lo permita. La identidad y participación reales no se ocultan ni se atribuyen títulos inexistentes. Una exigencia verificada del documento prevalece sobre la preferencia de presentación.
- Nombre y cédula del MVZ responsable separados de la firma de quien realizó la consulta; usar esos datos requiere autorización vigente. No copiar su firma automáticamente.
- Se pueden guardar borradores sin completar; no se puede emitir el documento nuevo sin esta atribución y firma. No inferir al consultante a partir del preparador o del responsable.
- Controlados: prescripción, autorización, emisión y dispensación solo por MVZ habilitado con permiso propio, sin delegación de esas facultades.

### Controlados

No admiten autorización permanente ni firma prestada. La autorización y emisión corresponden al responsable habilitado con su permiso propio. Se preservan las comprobaciones de producto, fuente, formato verificado y folio capturado. Preparar un borrador no elimina estos requisitos para emitir. La lista global de controlados sigue en la fase acordada posterior; este bloque no la inventa.

### Histórico y acceso

Las recetas emitidas conservan snapshot/PDF/hash y autoría original. Nuevos metadatos quedan vacíos en históricos: no reconstruir quién autorizó a partir de un puesto, una firma o `created_by`. Una receta histórica no concede autoridad para otra nueva.

Lectura por clínica, paciente/caso y permisos explícitos; eliminar el acceso universal por puesto admin en recetas. Preparadores y responsables no conservan acceso al perder sus permisos o salir de la clínica. La consulta/exportación tras vencer beta respeta los permisos de lectura y no permite emitir.

## Esquema concreto para revisar

Nombres propuestos, no columnas ya existentes ni SQL ejecutado.

| Entidad existente | Adición / restricción propuesta |
|---|---|
| `professional_delegations` | `document_type`, `authority_grant_id`, `grantor_member_since`, `recipient_member_since`, `profile_version_id`. Conjunto completo para nuevas autorizaciones; NULL en legado. `document_type='ordinary_prescription'` en este corte. Conservar fechas, titular, destinatario, caso y revocaciones existentes. |
| `prescriptions` | `prepared_by`, `prepare_grant_id`, `prepared_member_since`; `authorized_by`, `authorized_at`, `authorization_mode` (`individual`/`standing`), `authorization_grant_id`, `authorization_profile_version_id`; `issued_by`. Reutilizar `prepared_at`, `issued_at`, `delegation_id`, `snapshot`, `content_hash`, `pdf_hash`, `revision` y `created_by`. |
| `prescriptions` | En modalidad individual, autorizar ligado a la revisión/contenido exactos. En permanente, exigir `delegation_id` vigente del responsable, tipo/alcance coincidentes y referencia al acto previo; `authorized_at` representa la fecha de ese acto previo, no la hora ficticia de una revisión individual. |
| Snapshot PDF | Versión de esquema, actor preparador, responsable, acto de autorización y referencia, emisor, fechas y rótulos explícitos. Sin exponer evidencia privada ni imágenes de firma por la lectura de perfiles. |

Las referencias deben validar coincidencia de clínica, usuario, versión de perfil, código de permiso y época de membresía; una FK aislada no basta. Nuevas autorizaciones son inmutables y su retiro es anexo. Una salida/reingreso no reactiva autorizaciones antiguas. Renovar una concesión no debe revivir automáticamente una autorización atada a otra concesión vencida o revocada.

## Fases y riesgos

1. **Contrato y backend local:** restringir helpers específicos de recetas, RPC/políticas de lectura, preparación, autorización y emisión; impedir nuevas delegaciones heredadas de firma/dispensación. Revisar todas las definiciones posteriores y los accesos directos. Riesgo: un helper compartido cambia también formatos/reportes; inventariar sus consumidores antes de sustituirlo.
2. **PDF y Flutter:** flujo separado para preparar, autorizar y emitir; distinguir revisión individual/permanente. Los borradores pueden estar incompletos. La generación del documento para emisión y `rx_pdf_register` deben exigir la firma propia de quien realizó la consulta y la evidencia de autorización correspondiente. Riesgo: hoy el contrato de artefactos exige una firma; no simularla con una firma vacía ni reutilizar un PDF que cambió de contenido.
3. **Pruebas locales y GitHub:** matriz de permisos, contenidos/PDF, concurrencia, revocación, vencimiento y aislamiento. Riesgo: el vencimiento durante una espera requiere comprobar reloj real después de adquirir bloqueos.
4. **Revisión y corte conjunto:** solo tras revisar el resto de rutas y pruebas reales. No desplegar 13H por separado, publicar un APK incompatible ni activar beta como parte de esta propuesta.

Orden de bloqueos propuesto para mutaciones relacionadas: clínica → ledger cuando corresponda → caso → identidades en orden estable → receta/perfil. Confirmar contra las rutas existentes y probar carreras, incluida edición de perfil, antes de fijarlo. No añadir un bloqueo de clínica dentro de una función que ya bloqueó receta sin revisar el orden inverso.

## Pruebas de aceptación del bloque

- Preparador con permiso, sin cédula, crea/prepara y no autoriza por sí mismo.
- Puesto MVZ sin verificación; verificación sin permiso; permiso sin verificación: ninguno autoriza.
- Responsable distinto del perfil elegido: rechazo, sin usar una firma ajena como sustitución.
- Preparación con datos versionados del MVZ → autorización → PDF → emisión; preparador y autorizador distintos, con fechas servidor.
- Permanente vigente, vencida, revocada, de otro caso/tipo/destinatario/clínica; salida/reingreso de cualquiera de las partes.
- Revocación de permiso, habilitación o delegación entre preparar, generar PDF y emitir; reintento no elude la revocación.
- Cambio de nombre/cédula o contenido invalida la autorización pendiente; PDF histórico emitido permanece inmutable.
- Controlado rechaza autorización permanente y dispensación por preparador no habilitado.
- Dos confirmaciones simultáneas emiten una sola vez; cambios de versión/hash rechazan confirmación obsoleta.
- PDF de autorización previa no afirma revisión individual ni estampa firma individual ficticia.
- anon, tabla directa, RPC y Edge; otra clínica no lee perfiles, evidencia ni recetas; beta vencida permite solo lectura/exportación autorizadas.

## Alcance de autorización permanente y decisiones registradas

1. Alcance inicial de autorización permanente: caso + tipo (propuesto), o toda la clínica + tipo. La segunda opción requiere definir explícitamente qué casos futuros cubre y cómo se acepta al responsable.
2. Atribución y separación de firmas aprobadas: nombre/firma propia de quien realizó la consulta siempre; datos del MVZ responsable por separado. No queda pendiente volver a pedir esta aprobación. Si un requisito verificado exige además firma individual del MVZ, capturar ese acto real por la ruta individual; no fingirlo mediante una casilla de compartir firma.

Estas son decisiones de producto y alcance. No declaran cumplimiento normativo ni sustituyen la revisión del MVZ sobre los documentos emitidos.
