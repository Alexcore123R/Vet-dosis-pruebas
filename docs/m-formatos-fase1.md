# M-FORMATOS — fase 1 implementada localmente

## Alcance y estado real

Fase 1: plantillas de consentimiento de referencia y copias clínicas, constructor de preguntas/cláusulas, versiones, aprobación clínica, borradores por paciente, firmas propias del tutor y MVZ, generación de PDF en servidor y confirmación del archivo exacto. Acceso desde **Formatos** en el menú.

**Preparado y probado localmente; aún no instalado en Supabase remoto.** M4 y esta adaptación deben aplicarse y la función `forms-pdf` debe desplegarse antes de probar cuentas reales. No se han creado documentos, firmas, pacientes ni archivos reales en el servidor del usuario. Android/iPhone y exportación con dispositivos reales siguen pendientes de la prueba final acordada.

Pasante equivale al rol `auxiliar` existente: ningún rol nuevo, conversión de miembros o selector de permisos. Esta fase no emite recetas ni reportes oficiales de medicamentos controlados.

## Plantillas y aprobación

Cinco estructuras originales de referencia: general, quirúrgico/anestésico, eutanasia, alta anticipada e ingreso hospitalario. Estado de fuente: **sin verificar**. No se copian textos, membrete, logos ni instrucciones clínicas de los PDFs adjuntos. Anexos oficiales/control farmacológico se integrarán en fase 3, con fuentes verificadas.

Cada clínica parte de una estructura base y edita su copia; conserva la versión base exacta. Puede agregar texto, número decimal, fecha, casilla, selección única/múltiple, tablas repetibles y cláusulas propias. Información, docencia e indicaciones preoperatorias/recuperación se capturan por la clínica/MVZ; no se infieren dosis, diagnósticos, ayunos o protocolos.

Identificación de paciente/propietario, MVZ/cédula, firmante/número, firmas, privacidad y cláusula de revocación tienen definiciones protegidas tanto en cliente como servidor. Los campos de eutanasia específicos también están presentes como obligatorios; se llenan, no se borran. No hay formulación «irrevocable» en las referencias.

- Copia pendiente de revisión: puede guardarse, pero no crear un consentimiento nuevo para firma.
- Copia aprobada por clínica: permite crear documentos. Esta aprobación no acredita revisión normativa/global ni aceptación del tutor.
- Editar o restaurar crea otra versión; no cambia las anteriores ni actualiza documentos existentes.
- Historial muestra versión, fecha, autor, motivo y estado. La bitácora existente conserva las acciones e identificadores.
- La publicación de bases está reservada a administración del servidor, sin endpoint de escritura global en la app. La interfaz de administración global y su catálogo ampliado se desarrollarán aparte; el cliente no puede convertirse en administrador global.

El administrador configura membrete/logo iniciales por clínica con vista previa; cada guardado anexa una configuración. Nuevos documentos toman esos valores y pueden ajustar su presentación antes de firmar. El logo acepta PNG/JPG hasta 250 KB; el servidor valida tipo/dimensiones y conserva los bytes utilizados. Cambiar configuración no modifica archivos emitidos.

## Estados del documento

| Estado | Significado |
|---|---|
| `draft` / Borrador | Datos editables; si se asignó a auxiliar, están pendientes de revisión del MVZ. No hay consentimiento finalizado. |
| `awaiting_review` / Pendiente de generar PDF | El MVZ preparó el contenido y capturó ambas firmas. Falta registrar/generar el PDF para revisión. Las firmas dibujadas aún no bastan para finalizar. |
| `ready` / Listo para revisión y aceptación | El servidor conserva el PDF completo con firmas, listo para que tutor/MVZ lo revisen y confirmen. |
| `signed` / Firmado | El MVZ confirmó la aceptación del tutor sobre ese PDF/hash. Datos, versiones, firmas y PDF inmutables para los roles de aplicación. |

La identidad del usuario autenticado que prepara/confirma queda registrada. La app registra la aceptación declarada durante el flujo supervisado por el MVZ; no identifica biométricamente al tutor ni certifica firma electrónica avanzada. El número de identificación es capturado, no verificado automáticamente.

## Dónde se genera el PDF y cómo coincide

1. El MVZ guarda el borrador. Paciente y propietario se vinculan desde M4 y se congelan sus datos mínimos; no se exponen dirección, teléfono o documentos de identidad del propietario al auxiliar.
2. El tutor y MVZ dibujan sus propias firmas. El servidor valida los trazos, registra hora UTC de captura/preparación y congela contenido, valores tipados, versión y membrete/logo en una instantánea con SHA-256.
3. **Supabase Edge Function `forms-pdf`** renderiza esa instantánea usando `pdf-lib`, fuente Unicode incluida y PNGs de firma generados desde los trazos. No obtiene imágenes por URL externa ni hace cálculos clínicos.
4. Una RPC exclusiva del rol de servicio registra PDF y PNGs en tablas privadas mediante una transacción y calcula sus hashes sobre los bytes reales. El cliente no puede subir su propio PDF como final. La función vuelve a comprobar acceso autenticado antes de devolver el archivo.
5. Flutter recibe los bytes y comprueba SHA-256. `PdfPreview` permite revisar todas las páginas con las firmas ya incluidas. Una casilla expresa exige confirmar que tutor y MVZ revisaron el documento completo.
6. Finalizar aporta ID, revisión y hash revisado. El servidor verifica responsable/rol vigentes y archivo correspondiente. **No renderiza, agrega páginas ni cambia fechas o marcas al confirmar**: conserva exactamente los bytes que se mostraron.
7. La hora de captura/preparación aparece en PDF; la hora de aceptación final se almacena aparte en el registro/bitácora del servidor. Se mantiene esta distinción para no alterar el archivo aprobado con un sello posterior.
8. Si cambia el contenido antes de confirmar, se anulan firmas/PDF/revisión previos y se requiere el proceso de nuevo. Una edición concurrente provoca conflicto. Repetir una confirmación exitosa no duplica la firma ni la bitácora.

En esta implementación los archivos están en **Postgres privado** (`private.form_artifacts`), con límite de 2 MB por PDF. Las firmas/imágenes están protegidas por el documento. No se utilizan enlaces públicos ni caché clínica offline. Esto permite registrar archivo y hash atómicamente; si más adelante se migra a Storage, habrá que conservar inmutabilidad y coordinar preparación/finalización entre ambos servicios. Un administrador de infraestructura siempre conserva capacidades de administración de la base; la protección no se presenta como almacenamiento WORM certificado.

## Identificación y firmas

Solo se guarda **nombre y número de identificación del firmante**. No existe campo de fotografía de INE/DNI ni se solicita subir su imagen. La imagen PNG de la firma es un artefacto diferente y requerido para el documento firmado.

La fase 1 usa firma propia del tutor y del MVZ responsable. Perfiles profesionales reutilizables, habilitación clínica de admins, firma compartida/delegaciones y restricciones de recetas se integran con fase 3/M6; los permisos ya acordados permanecen en el diseño, pero todavía no son funciones disponibles aquí.

## Eutanasia

El consentimiento recoge antes de autorizar: motivo clínico, concepto previo del MVZ (texto descriptivo), procedimiento, método propuesto, información explicada, disposición del cuerpo y costo/condiciones acordadas, junto con tutor, MVZ, firmas, privacidad y revocación.

**Constatación de muerte es posterior**, mediante entrada clínica vinculada en fase 2: quién constató, método/observación documentada y hora del servidor. No se exige declarar la muerte antes de firmar ni rellenar retrospectivamente el consentimiento. Disposición/costo acordados y su ejecución posterior también deben distinguirse si cambian. No hay método o dosis de eutanasia precargados.

## Permisos

- Admin: copias/versiones y configuración; consulta documentos de su clínica. No pasa a ser MVZ por compartir firma o capturar una cédula.
- MVZ: edita las plantillas de las que es responsable, usa copias clínicas aprobadas, crea sus documentos, asigna un borrador a un auxiliar y prepara/finaliza sus firmas.
- Auxiliar: consulta plantillas y llena únicamente borradores expresamente asignados. No prepara firmas/PDF final ni accede a imágenes de firma/documentos finalizados del caso. No se le amplía acceso general a propietarios.
- Otro MVZ no responsable: no lee ni firma documentos ajenos; no edita la plantilla de otro salvo contar con el rol administrativo.
- Recepción/estilista: sin acceso clínico a este módulo.

Se revalidan permisos en RPCs y RLS, además de la UI. Cambiar sesión/rol/clínica cierra rutas privadas mediante la identidad del MaterialApp existente. No se ponen expedientes, identificaciones o firmas en preferencias/outbox.

## Tablas y despliegue pendiente

Adaptación nueva `supabase/adaptations/existing_forms_phase1.sql`, una vez después de M2 y M4. Añade `form_templates`, `form_template_versions`, `form_documents`, `form_signatures`, `clinic_document_settings` y `private.form_artifacts`. Reutiliza `audit_log`, roles, pacientes/propietarios y comprobantes privados de idempotencia. No altera las seis tablas iniciales ni roles. El documento conserva la versión mediante FK, JSONB estructurado validado y PDF privado; la adaptación de [fase 2](m-formatos-fase2.md) añade los hechos clínicos sin sustituir estas tablas.

Para el despliegue futuro: aplicar dependencias/adaptación y desplegar `forms-pdf` en el proyecto correspondiente con Supabase CLI. `supabase/config.toml` incluye fuente/licencia como archivos estáticos e importaciones. `verify_jwt=false` desactiva solo la validación antigua del gateway; **la función exige Bearer y valida al usuario mediante `auth.getUser()`**, y las RPCs revalidan clínica/rol. No acepta llamadas anónimas. Las credenciales de servicio son secretos de la función Supabase, nunca argumentos Flutter ni claves pedidas al usuario para compartir en chat.

## Verificación

- Flutter: análisis, pruebas de campos/unidades/fechas, identificación mínima, hash corrupto, revisión invalidada, roles, limpieza por fallos y pantallas de teléfono; suite total 69 pruebas.
- `bash supabase/tests/run.sh forms`: PostgreSQL aislado, datos sintéticos, RLS/roles/asignación, definición protegida, firma, permisos exclusivos de registro binario, hash, reintento, conservación del consentimiento firmado tras editar/restaurar plantilla y triggers contra alterar documento/firma/PDF histórico. Los bytes sintéticos de esta prueba ejercitan las invariantes de DB; la validez PDF se prueba en el renderizador.
- `npm ci --prefix supabase` y `npm --prefix supabase run test:renderer`: cuatro pruebas del generador real con PDF multipágina, texto/acentos, campos de eutanasia, firmas PNG, logo y rechazo de trazos/imágenes inválidos. Inspección visual de PDF sintético sin datos reales.
- `npx deno check --config supabase/functions/forms-pdf/deno.json supabase/functions/forms-pdf/index.ts`: chequeo del servidor.
- Compilación web configurada; queda prueba integrada Auth/Edge Function/DB en Supabase remoto y exportación/impresión en teléfonos reales. Ninguna prueba local sustituye esas comprobaciones finales.

## Siguientes fases aprobadas

2. [Fase 2 implementada localmente](m-formatos-fase2.md): historia clínica/hoja quirúrgica, roles separados por acto, observaciones y constatación posterior vinculadas a M4. El enlace estructurado de medicación con M5 se incorpora con M6.
3. Con M6: perfiles/delegaciones, recetas, registro único de medicación, validación de controlados, frascos y reportes. POS/inventario se conectan en M8. Mantener prohibición de preparar/emitir controlados para auxiliares, incluso con firma compartida.

La fase 2 amplía la lectura de documentos clínicos firmados a profesionales/auxiliares autorizados por caso; los consentimientos conservan la restricción descrita en fase 1.
