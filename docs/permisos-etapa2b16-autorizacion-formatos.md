# Formatos: atención, autorización individual, tutor y PDF

Candidato local **13J4**, después de 13J3. No aplicado al proyecto Supabase, sin APK ni apertura de beta. Sustituye la limitación de emisión de documentos nuevos descrita en 13J3 solamente cuando está disponible el contrato nuevo válido.

## Estado y alcance

- **Implementado y probado anteriormente:** borradores y firma propia de elaboración 13J3; las otras rondas tienen su evidencia independiente.
- **Preparado localmente en esta ronda:** atención/explicación con firma propia, revisión individual del MVZ, firma presencial del tutor tras ver el documento, PDF congelado y emisión por permiso explícito.
- **Aplicado en remoto y probado:** ninguna migración o función de esta ronda. GitHub ejecuta pruebas aisladas, no Supabase.
- **Pendiente:** adaptación de otras pantallas clínicas y navegación, rutas transversales de permisos/agregados/respaldos, pruebas reales Auth/Storage/Edge con dos clínicas y teléfono, despliegue conjunto revisado y apertura de beta.

## Flujo y facultades

`draft → awaiting_authorization → awaiting_tutor → awaiting_review → ready → signed`.

Una hoja clínica omite `awaiting_tutor`. La persona que elabora selecciona explícitamente quién realizó la atención o explicó el consentimiento. Cambiar esta selección incrementa la revisión y deja sin efecto las firmas de la versión anterior. Cada persona atestigua desde **su propia sesión**, con nombre, firma dibujada y confirmación; no existe un parámetro para firmar como otra cuenta. El nombre de puesto no se imprime ni concede facultades.

Para un consentimiento, la atestación acredita su **explicación**, no una cirugía u otro procedimiento realizado. En una hoja clínica se exige un caso existente del mismo paciente/clínica/responsable y autorización vigente del caso y del tipo de procedimiento (`evaluacion`, o `cirugia` para hoja quirúrgica). No se convierte un puesto en habilitación. Los integrantes clínicos que se consignen deben ser elegibles para cirugía/anestesia; sus nombres reportados no se convierten en firmas ni actuaciones nuevas.

Quien elabora solicita revisión de esa versión exacta. Solo el MVZ responsable seleccionado, habilitado y con `form.authorize`, puede autorizarla mediante confirmación explícita. Se registra el acto individual con concesión, perfil profesional, pertenencia y hora del servidor. **No se inserta la firma de su perfil**. Esta ronda no añade autorización permanente para formatos, prescripción ni controlados.

En consentimientos se genera una vista previa privada del contenido autorizado, pendiente de firma. El tutor revisa ese archivo y firma personalmente en el dispositivo; quien captura confirma el acto. Se conserva nombre/número de identificación, firma, cuenta capturadora, hora y hash de la vista previa. Esto acredita captura declarada en presencia, no autenticación remota de la identidad del tutor. Nunca se permite sustituirla por firma profesional guardada o una delegación.

Después se genera el PDF final con firmas separadas de elaboración, atención/explicación y tutor cuando corresponde, datos del MVZ y registro de su autorización. El emisor revisa esos bytes exactos. Nuevo permiso explícito `form.issue` permite confirmar la emisión **solo** con toda la cadena vigente; no se concede automáticamente a nadie ni sustituye `form.prepare`/`form.authorize`.

Las referencias clínicas nuevas usan una cláusula neutral de atribución. Se insertan versiones globales nuevas como **sin verificar**, sin reescribir ni aprobar las de clínica. Para emitir con el flujo nuevo, la clínica debe revisar una versión basada en esa referencia; los borradores de la referencia antigua no se aprueban automáticamente. Los históricos firmados permanecen intactos.

## Evidencia y concurrencia

`private.form_flow_events` conserva de forma anexa atención, solicitud, autorización, captura del tutor y emisión, con revisión/hash, actor, concesión y pertenencia. `private.form_flow_artifacts` conserva vista previa/final por documento/revisión; gana el primer artefacto registrado. Ninguna tabla privada concede lectura directa a usuarios o servicio.

Se comprueba autoridad vigente después de los bloqueos y al registrar el artefacto después de renderizar, no solo al abrir la pantalla. El PDF tiene hash y límite de tamaño. El renderer rechaza identidades desconocidas, falta de firma, mezclas con receta, tutor ausente en consentimiento final y uso de vista previa como documento final. El servicio renderer sigue siendo un componente confiable; las pruebas SQL de frontera usan encabezados sintéticos, y la integración aparte renderiza PDFs reales desde snapshots sintéticos generados por PostgreSQL y verifica texto e imágenes.

La confirmación concurrente conserva una sola emisión y el mismo PDF. Corregir requiere motivo y nueva revisión; conserva eventos y archivos anteriores pero exige firmas/autorización nuevas. Un documento firmado no se reabre ni se regenera. Históricos conservan su PDF original y las consultas de metadatos no devuelven vectores de firma.

## Captura clínica flexible

El borrador admite captura parcial. Para enviar a revisión se aplican los campos mínimos de la plantilla aprobada, sin imponer SOAP, peso ni temperatura completos. Si se captura una medición, se valida tipo, signo y fecha/hora, sin inventar rangos normales ni rellenar vacíos.

Este candidato vincula la hoja al **caso existente**. No llama al publicador clínico antiguo: no crea una consulta, SOAP, observación, aplicación, cirugía ni consentimiento por el hecho de emitir un PDF. La captura de actos y observaciones sigue por sus rutas tipadas independientes. Las pantallas clínicas antiguas que suponían publicación automática deben adaptarse antes del despliegue conjunto.

## Interfaz y compatibilidad

Contrato `form_document_workspace`: `mode=individual_forms`, `schema_version=1`, `flow_version=1`. Contrato por documento `form_document_flow` con acciones independientes y opciones de personas/casos/campos provenientes del servidor. Flutter descarta capacidades al perder contrato/acceso, rechaza versiones desconocidas y no retrocede al modo anterior después de conocer este flujo. La edición usa borrador; revisión/firmas/emisión se presentan como etapas distintas. Los controles de confirmación parten sin marcar y las personas no se seleccionan automáticamente.

La vista previa del tutor y el PDF final no permiten compartir/imprimir antes de la emisión. La vista previa del tutor tiene aviso de firma pendiente. PDF original firmado sí permite exportar. Las comprobaciones de acceso real de Edge y Storage permanecen pendientes del entorno de pruebas desplegado.

## Validación reproducible

- `bash supabase/tests/run_form_individual_workflow.sh`: dependencias anteriores completas, SQL sintético, permisos por sesión, revocación tras snapshot, hoja clínica enfocada sin mediciones, corrección anexa, PDF real desde snapshots, concurrencia y vencimiento después de esperar un bloqueo.
- `flutter test --no-pub test/form_individual_workflow_test.dart`: contrato, ausencia de autoridad implícita, selección explícita, confirmación y pérdida de acceso.
- `npm run test:renderer --prefix supabase`: regresiones de recetas, controlados, membrete y firmas.
- `flutter analyze --no-pub` y batería Flutter completa.

Validación local: **328 pruebas Flutter correctas** en la batería completa; las **5 pruebas del flujo** se repitieron tras los últimos cambios de presentación y pasan. Análisis sin incidencias; **15 regresiones del renderer correctas**. SQL y renderer desde PostgreSQL, concurrencia de emisión/corrección y vencimiento tras bloqueo correctos. El enlace final de CI se registra tras la ejecución. Ninguna referencia clínica o normativa se incorpora/verifica en esta ronda.
