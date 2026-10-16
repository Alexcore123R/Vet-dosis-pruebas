# 2B-15: borradores y firma propia de elaboración

Candidato local **13J3**, después de 13J2, 16-oct-2026. No desplegar aisladamente ni abrir beta: todavía no autoriza/emite documentos nuevos ni captura la aceptación firmada del tutor.

## Estado

- **Implementado y probado:** plantillas/membrete 13J2, reportes y rondas anteriores, con evidencia aislada documentada.
- **Preparado local:** borrador con autor y MVZ seleccionado explícitamente; firma inmutable de elaboración ligada a contenido/revisión; lectura segura y Flutter sin firma compartida en este flujo.
- **Aplicado en remoto y probado:** no aplicado a Supabase. Las pruebas de CI usan bases aisladas; no equivalen a despliegue.
- **Pendiente:** autorización individual y posterior emisión, PDF exacto con identidad real, firma del tutor no delegada, atribución de la atención clínica cuando corresponda, corrección/reselección explícita de un borrador cuya autoridad cambió y conexiones clínicas que aún llaman rutas antiguas. Después, dependencias transversales y pruebas reales Auth/Storage/Edge/APK.

## Lo que registra y lo que no acredita

`form.prepare` con lectura de paciente y clínica permite elaborar un borrador propio; no exige habilitación profesional al personal que prepara. No permite realizar tratamientos o cirugías. La firma `document_authorship` acredita **la elaboración y revisión de esa versión**, con nombre declarado, firma dibujada y sesión del propio autor. No afirma que realizó una consulta/procedimiento, no es autorización del MVZ, no es aceptación del tutor y no delega firma ajena. La identidad de quien realmente realizó la atención debe conectarse explícitamente antes del PDF final cuando corresponda; no se deduce del preparador.

El MVZ se elige manualmente, sin opción preseleccionada. Debe tener habilitación contrastada vigente, perfil coherente y permisos actuales `form.authorize`, `clinical.read`, `patient.read`. Su selección **no registra autorización**. Su nombre/cédula se obtienen del perfil verificado y se separan del autor; los valores enviados por el cliente no los sustituyen. No se toma su firma del perfil.

La plantilla debe ser una versión de clínica aprobada mediante el proceso 13J2 con concesión y perfil del revisor registrados. Las plantillas antiguas aprobadas no se convierten automáticamente: se prepara/revisa una versión nueva. La aprobación no verifica datos clínicos ni certifica validez normativa.

## Datos y vigencia

Nueva tabla privada `form_authorship_attestations`, append-only, sin acceso directo de cliente/servicio. Guarda documento, revisión, hash SHA-256 de contenido, identidad de sesión, nombre, puntos de firma, época de pertenencia, concesión concreta y fecha del servidor. No hay migración automática de firmas o habilitaciones anteriores.

El contexto del borrador congela las concesiones seleccionadas, las épocas de pertenencia y la versión del perfil responsable. Después de un cambio/revocación/vencimiento no se resucita la autoridad con otra concesión. Hará falta una acción explícita de corrección/reselección en la fase de autorización; en esta fase debe prepararse otro borrador.

El hash incluye paciente, clínica, versión de plantilla, responsable, autor, valores, membrete y snapshot. Cambiar cualquier dato o la revisión exige otra firma; la evidencia previa se conserva, no se sobrescribe ni reaprovecha. Un reintento válido devuelve el mismo recibo; verifica autoridad actual antes de devolverlo.

Bloqueo: clínica/libro → identidades ordenadas → documento; se comprueba vigencia con hora real después de esperar. La firma no crea casos clínicos, no aplica medicamentos, no acepta el consentimiento y no publica observaciones.

## Guardado e interfaz

Guardar borrador usa validación parcial: permite datos clínicos opcionales pendientes. No impone anamnesis completa, SOAP completo, peso ni temperatura para guardar. Se mantienen los tipos y unidades de los campos que sí se capturen; vacío no se interpreta como normal.

Contrato nuevo `form_document_workspace`, versión 1, modo `draft_authorship`: lectura/preparación, responsables elegibles y versiones de plantilla elegibles. Flutter valida forma y tipos; la pérdida del contrato conocido o una respuesta incompatible borra datos/capacidades y no vuelve a permisos por puesto. El permiso de plantilla por sí solo no abre documentos.

La nueva ruta de edición ofrece firma de elaboración propia, exige confirmación y bloquea doble envío. No muestra selección de firma prestada, firma del tutor, asignación por puesto ni botón de emisión. El servidor liga `signer_id` a la sesión: no existe parámetro para firmar por otra cuenta. Si la persona que realizó la atención es otra, no se debe usar esta firma de elaboración para atribuirle esa atención.

## Rutas antiguas e históricos

Las mutaciones antiguas de creación sin responsable explícito, preparación/finalización por puesto, uso de firma de perfil y asignación por puesto quedan cerradas en este candidato. El registro de PDF nuevo también queda cerrado hasta la fase de autorización. Por eso no se despliega 13J3 sin completar el siguiente bloque; las pantallas clínicas antiguas todavía deberán adaptarse.

Lectura de documentos exige lectura clínica/paciente y relación explícita como autor con preparación, responsable habilitado con autorización, o acceso clínico al caso publicado del documento firmado. No hay acceso automático de administrador. Listas omiten puntos de firma y contexto privado; tablas de documento solo permiten `id/clinic_id` para resolución de ámbito de Edge, y firmas no se leen directamente.

La consulta de ámbito/snapshot de un histórico firmado devuelve datos seguros sin vectores de firma; Edge recupera el PDF existente y no lo vuelve a renderizar.

Un documento histórico **ya firmado** conserva su artefacto original/hash y puede consultarse con autoridad actual de lectura. No se vuelve a emitir, no se cambia su firma y no se transforma en una atestación nueva. Los borradores antiguos necesitan el flujo nuevo; no se promueven por conversión automática.

## Decisiones y siguiente fase

Este bloque concreta lo autorizado: preparación por persona, identidad/firma propias, responsable separado y tutor no delegado. No añade datos clínicos, normas ni una autorización permanente general. La nueva tabla almacena la evidencia técnica de firma ya aprobada, sin ampliar facultades clínicas.

Siguiente fase: revisión/autorización de contenido exacto por el MVZ, identificación de quien realizó la atención cuando sea distinto, aceptación y firma real del tutor en consentimientos, artefacto/PDF inmutable y emisión idempotente. Mantener una distinción visible entre elaboración, atención y autorización. No insertar una firma del MVZ cuando solo prestó sus datos profesionales o dejó permisos.

## Validación

Pruebas SQL con datos ficticios: responsable explícito habilitado; autor con puesto visual estilista; nombre/cédula del responsable no falsificables desde valores; nombre/firma/confirmación obligatorios para atestación; sin firma del tutor/acto clínico; hash/revisión exactos; tabla privada/append-only; lectura aislada y rutas antiguas cerradas; perfil/responsable revocados; archivo histórico preservado. `%PDF-SYNTHETIC-ARCHIVE` es fixture de transporte, no un PDF nuevo real.

Concurrencia: una atestación por reintento simultáneo, revocación mientras espera y vencimiento después del bloqueo, sin guardar una firma vencida. Flutter: contrato estricto, plantillas elegibles, pérdida de contrato, sin firma prestada/emisión, confirmación propia y bloqueo de doble envío.

Validación local: **323 pruebas Flutter correctas**, análisis sin incidencias, y 7 pruebas enfocadas de firma/salida sin perder cambios tras el último ajuste de interfaz. SQL y concurrencia correctos, incluido borrador clínico sin SOAP/mediciones obligatorios. GitHub Actions: [ejecución 38975359759](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38975359759), commit de código `d2ddbf8`: **16/16 trabajos correctos**, incluido `form-document-drafts` y regresiones de plantillas, reportes, recetas, inventario/caja y hospitalización. La primera ejecución `38975144647` también pasó; la última incluye la protección de vectores de firma en la consulta de históricos. Pruebas aisladas, sin despliegue a Supabase ni APK.
