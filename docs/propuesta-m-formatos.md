# M-FORMATOS — propuesta para aprobación

Estado: estructura aprobada por el usuario, con ajustes de contenido por clínica y logo, 7 de octubre de 2026. La aprobación permite comenzar la implementación local; no se escribió implementación ni migración para este módulo en esta revisión y no se modificó Supabase. Se cumplió la instrucción de revisar y proponer antes del código. Las pruebas reales y aplicación remota siguen pendientes para el final.

La fase 1 tiene una [implementación local y alcance documentado](m-formatos-fase1.md): usa artefactos binarios en Postgres privado para registro atómico, no Storage en esta etapa; datos clínicos/delegaciones/recetas se integran en fases 2/3.

La [fase 2 tiene implementación local](m-formatos-fase2.md), con casos, hechos clínicos y autorizaciones por procedimiento.

La [adenda de controlados, frascos y docencia](adenda-controlados-y-docencia.md) incorpora los ajustes posteriores del usuario y prevalece en permisos para controlados: compartir firma no autoriza a un auxiliar/pasante a preparar o emitir recetas controladas, validarlas o generar reportes oficiales. Pasante se representa mediante el rol auxiliar existente; añade habilitación MVZ separada del rol administrativo, revisión y libro de frascos.

## 1. Qué se revisó y qué ya tenemos

Revisión de las capturas/metadatos suministrados y del código, migraciones y permisos locales. No es una inspección autenticada actual del servidor remoto.

- Base existente: `clinics`, `clinic_members`, `Fármacos`, `Fármacos personalizados`, `inventario`, `lotes_inventario`.
- M2: adaptación aplicada según confirmación del usuario; reutiliza membresías, roles de servidor, `audit_log` y funciones privadas de autorización. Falta la prueba real autenticada acordada para el final.
- M4: `vet_owners`, `vet_patients`, `vet_patient_events` y comprobantes privados de idempotencia. Preparado y probado localmente, todavía no aplicado remotamente. SOAP, peso y prevención ya son eventos con campos estructurados y validación. El consentimiento actual conserva texto exacto y firma como coordenadas, pero todavía no tiene versión de plantilla, imagen, PDF congelado ni hash.
- M5: `hospital_stays` y `hospital_tasks`, con confirmación, autor/hora del servidor y auditoría. Preparado y probado localmente, todavía no aplicado remotamente. Los medicamentos de las tareas actuales son indicaciones escritas; falta el vínculo a un registro farmacológico estructurado.
- M6 aún no tiene tablas de recetas, perfiles profesionales ni libro de control. Las tablas propuestas abajo serán compartidas por M6 y M-FORMATOS, en vez de implementar dos conjuntos equivalentes.

No se reemplazan pacientes, propietarios, roles, inventario, hospitalizaciones, catálogo farmacológico ni bitácora.

## 2. Referencias recibidas

Los cinco originales se conservan en `docs/formatos-referencia/`, únicamente para revisión. No son plantillas listas para producción ni acreditan vigencia normativa. No se trasladan a la app su membrete, dirección, decoración o texto.

| Archivo | Contenido observado | Uso propuesto |
|---|---|---|
| 1 — Formatos de control… Grupo I | Dos páginas: registro Grupo I y registro Grupo II; instrucciones, unidades de producción, recetas, productos, lotes, tratamientos y retiro | Estructura del registro y exportación; dos esquemas oficiales separados, pendientes de corroborar con una fuente vigente |
| 2 — Autorización…cccccc | Consentimiento anestesia/sedación/cirugía y hoja informativa de anestesia | Referencia para identificación, procedimiento, riesgos, alternativas y firmas; redacción propia |
| 3 — EUTANASIA | Autorización, identificación del tutor/animal, método y firma; incluye autorización relativa a muestras | Consentimiento específico; cualquier decisión sobre muestras se registra por separado, sin aceptación automática |
| 4 — SOLICITUD DE ALTA VOLUNTARIA | Solicitud de retiro anticipado y reconocimiento de información/riesgos | Formato de alta anticipada vinculado con hospitalización, recomendaciones y seguimiento |
| 5 — Autorización…general | Otra variante del consentimiento, hoja informativa y una hoja anestésica paciente × hora, fármacos/vía/cantidad y constantes | Unificar el consentimiento equivalente; conservar la hoja anestésica como formato clínico distinto |

Los consentimientos anestésicos contienen la palabra «irrevocable»: no se reproduce, porque el requisito nuevo exige revocación. La hoja informativa contiene indicaciones generales de ayuno y una descripción numérica de riesgo: no se convierten en protocolos o escalas verificadas. Indicaciones de preparación, clasificación ASA, límites de constantes y normativa requieren fuentes/versiones verificadas; en su ausencia, campos vacíos y estado «sin verificar».

No se recibió una hoja separada de historia clínica, ASA/EKG o consentimiento de ingreso hospitalario. Se propone su estructura original sin inventar sus resultados ni referencias.

## 3. Tablas nuevas propuestas

Todas las tablas de clínica tendrán `clinic_id`, identificador UUID, claves foráneas compuestas con clínica, y RLS. Los enlaces no podrán apuntar a otra clínica. Fechas de creación/firma y autores se asignan en servidor. Las siguientes son especificaciones, no SQL.

| Tabla | Campos principales y función |
|---|---|
| `form_templates` | Identidad de plantilla: ámbito `base/clinica`, clínica (nula solo para base), tipo, título, MVZ responsable, plantilla base de origen opcional y estado archivada. Una copia clínica y un formato creado desde cero son identidades independientes. |
| `form_template_versions` | `template_id`, número de versión, versión padre, `base_version_id` opcional, esquema estructurado de campos/secciones/cláusulas, versión del esquema del motor, estado de verificación, fuente, motivo, autor y hora. Solo anexado; una edición/restauración siempre crea otra fila. Una versión clínica incluye contenido completo independiente, marca de modificación y la referencia exacta de origen. |
| `private.form_global_admins` | Administradores globales del catálogo, asignados mediante administración de servidor. Un admin de clínica no puede darse este privilegio. No incluye autorización para leer expedientes o firmas de clínicas. |
| `private.form_catalog_audit` | Bitácora del catálogo global: publicación, autor, versión y resumen de cambio. Se separa de la bitácora clínica existente porque los cambios globales no pertenecen a una clínica. |
| `clinic_document_settings` | Membrete, logo privado configurable, contactos y URL del aviso de privacidad por clínica. Opción de incluir u omitir logo en la exportación PDF; validación de imagen, tamaño y formato, ajuste sin deformación y vista previa. Se congela una copia de los datos y los bytes del logo usados en cada documento emitido; sustituir o eliminar el logo de configuración no cambia documentos anteriores. |
| `professional_profiles` | Identidad del perfil profesional, titular `user_id` y clínica. |
| `professional_profile_versions` | Nombre, cédula capturada, clave de autorización/aprobación capturada cuando corresponda, firma propia opcional en almacenamiento privado, estado/fuente de verificación, autor y hora. No se considera una cédula verificada solo por escribirla. Versiones anexadas, sin sobrescribir las usadas antes. |
| `professional_delegations` | Perfil, titular, miembro receptor, alcances separados para usar datos/firma/tipo de documento, fecha de concesión, vigencia y revocación. Titular concede o revoca; ser admin no permite compartir la firma de otro médico. Cada emisión registra la autorización efectiva. Las firmas de tutores no son compartibles. |
| `form_documents` | Clínica, paciente, propietario/tutor relacionado, versión exacta, MVZ responsable/presentador, procedimiento, borrador y estado finalizado/firmado. Referencias a perfil y autorización; instantánea exacta de datos vinculados, membrete, contenido y aviso de privacidad. Una vez finalizado o firmado, queda inmutable. |
| `form_document_values` | Valores estructurados por `document_id`, clave estable del campo, fila repetible y tipo: texto, fecha/instante, booleano, selección, número exacto con unidad, o enlace a entidad. Restricciones según tipo y esquema. Permite consultar datos sin interpretar párrafos. Inmutables al finalizar el documento. |
| `form_signatures` | Documento, rol del firmante, nombre e identificación capturados, firma imagen privada, vínculo a perfil/delegación cuando sea profesional, hash de la firma y hora del servidor. Recoge la aceptación del tutor sobre el contenido exacto. Una imagen trazada no equivale automáticamente a una firma electrónica avanzada. |
| `form_artifacts` | PDF privado, versión del renderizador, tamaño, SHA-256 calculado sobre los bytes realmente almacenados, hora del servidor e instantánea de la versión. PDF final y firmas sin reemplazo/borrado por clientes. Vista previa temporal separada del archivo final. |
| `clinical_observations` | Paciente, documento y fila de origen, medición/clasificación, número exacto o selección, unidad, momento observado, responsable y hora de registro. FC/FR/temperatura/presión/TLLC, valoración ASA ingresada por el MVZ y hallazgo/archivo EKG, sin clasificaciones automáticas sin fuente verificada. |
| `prescriptions` | Clínica, paciente, MVZ responsable, perfil profesional/versiones/autor de captura, fecha, número interno, folio oficial capturado opcional, tipo y documento/PDF relacionado. M6 será su propietario funcional; M-FORMATOS reutiliza estas recetas. Un número interno nunca se presenta como folio oficial. |
| `medication_records` | Registro farmacológico único: paciente, receta opcional, documento, tarea hospitalaria opcional, producto/presentación, concentración/unidad capturadas y fuente/estado, cantidad/unidad/vía, lote opcional, momento, responsable y etapa perioperatoria opcional. Producto referido al catálogo validado o identificación manual explícita; no inventa dosis o clasificación. Registrar una orden no equivale a registrar administración. |
| `controlled_drug_entries` | Libro ligado al `medication_record`, receta, folio oficial capturado, clasificación y fuente/estado, datos de unidad de producción cuando corresponda, producto/registro/lote/unidades/dosificación/duración/retiro con unidad y fuente. Entradas/salidas identificadas por evento, sin doble conteo por copiar el fármaco a una hoja. Conservación con fuente normativa y estado de verificación. |

El contenido y las definiciones del constructor pueden usar JSONB estructurado; los valores clínicos, mediciones y movimientos se consultan mediante columnas tipadas y relaciones. No se guarda toda la información solamente en texto o dentro del PDF.

Los formatos oficiales se distribuyen como versiones base con política de bloqueo reforzada. El constructor no puede convertir un formato propio en «oficial», quitar columnas ni modificar su semántica. Solo un administrador global puede publicar una nueva versión oficial tras verificar la fuente.

## 4. Cambios a tablas y flujos existentes

| Elemento existente | Cambio aditivo propuesto |
|---|---|
| `vet_patient_events` | Añadir `form_document_id` opcional y vínculo inverso único por clínica/documento/tipo/elemento de origen. Ajustar RPCs para anexar SOAP, peso o prevención desde valores revisados, sin duplicarlos. Mantener históricos y firma de coordenadas existentes; etiquetarlos como registros previos, sin inventar PDF, plantilla o fecha pasada de firma. |
| `hospital_tasks` | Añadir `medication_record_id` opcional con vínculo de misma clínica. Prescribir desde una hoja genera la orden estructurada y la tarea mediante la misma operación autorizada. Confirmar administración produce el evento farmacológico/control correspondiente una sola vez. Tareas antiguas conservan sus indicaciones y no se reclasifican automáticamente. |
| `audit_log` | Reutilizar tabla y política actual. Añadir acciones de versión, delegación, presentación, emisión, restauración, corrección y revocación; IDs y resumen de diferencias, evitando copiar identificaciones, texto clínico o firmas. |
| `clinic_members` | Sin cambios de roles: pasante equivale a auxiliar por decisión del usuario. |
| `clinics`, propietarios/pacientes, inventario y lotes | Sin nuevas tablas equivalentes ni cambios de columnas previstos para M-FORMATOS. Las políticas y catálogos existentes se reutilizan. Consistencia de lotes e inventario sigue siendo tarea de M8. |
| RLS/RPC de M4 | Acceso acotado para auxiliares a borradores asignados. No ampliar el acceso general a `vet_owners` ni a consentimientos firmados para toda la clínica. Un RPC presenta únicamente los campos imprescindibles del tutor en el documento autorizado. |

No alterar las migraciones M2–M5 históricas para añadir M-FORMATOS. Tras aprobación se preparará una adaptación nueva, aplicada después de las dependencias y con comprobaciones previas. No se ejecutará remotamente durante esta fase de revisión.

## 5. Constructor, bloqueos y permisos

- Tipos: texto, fecha, casilla, selección única/múltiple, número con unidad, tabla repetible, firma y campo vinculado. Claves estables; etiquetas pueden mostrarse en español.
- Campos protegidos según tipo: paciente/animal, propietario/firmante, MVZ y cédula, firma, aviso de privacidad; cláusula de revocación en consentimientos. Bloquear significa impedir eliminar o alterar la definición, no impedir completar el valor. No se obliga a inventar un dato clínico desconocido.
- Un formato clínico u oficial que no sea consentimiento no recibe una cláusula de consentimiento ajena a su función. Las reglas obligatorias se definen por tipo en servidor, no con un interruptor manipulable por el cliente.
- Editables: membrete/logo, costos, secciones propias, preguntas extras, hoja informativa, indicaciones preoperatorias y de recuperación, y disposición permitida. Cada clínica redacta su contenido o parte de una propuesta original; no se obliga a utilizar el texto informativo base. Cada cambio crea una versión nueva, con autor y fecha. Un esquema nuevo debe conservar el conjunto obligatorio de su tipo y superar validación en servidor.
- Distinguir texto informativo e indicaciones capturadas por la clínica de recomendaciones clínicas verificadas por la app. El MVZ revisa las indicaciones para cada paciente. No se infieren dosis, horarios de ayuno, escalas o límites desde texto libre ni se incorporan automáticamente al catálogo o al motor de cálculo. Campos clínicos estructurados mantienen fuente y estado cuando corresponda.
- Admin de clínica y MVZ responsable asignado a la plantilla: crear/versionar la copia clínica, restaurar, previsualizar. Otro MVZ puede solicitar una copia propia bajo las mismas reglas. Auxiliar/pasante: leer plantillas permitidas y completar borradores asignados; no editar definición, atribuir consentimiento al tutor ni emitir una receta como MVZ. Recetas ordinarias delegadas se limitan a productos y actos permitidos conforme a la adenda; controlados excluidos.
- La firma propia profesional se usa con la identidad/cédula de quien firma. Los datos/firma compartidos usan autorización vigente y registran por separado titular, usuario actuante y responsabilidad. Una firma del tutor se captura para ese documento; nunca se reutiliza desde un consentimiento anterior.
- Cada lectura de PDF/imagen y cada emisión verifica usuario, clínica, rol, asignación y delegación. Archivos privados con URLs temporales, sin claves públicas permanentes. El retiro de autorización bloquea nuevas emisiones, no cambia documentos ya emitidos.
- Lectura de bitácora de plantillas mediante RPC filtrado para admin/MVZ responsable, preservando el acceso admin del `audit_log` actual.

## 6. Versionado, vista previa y firma inmutable

1. Elegir base publicada, copia clínica o formato propio; la pantalla muestra versión y aviso: «Plantilla de referencia. La clínica es responsable de revisar y aprobar el contenido final».
2. Editar una propuesta en memoria; previsualizar PDF marcado como borrador antes de guardar la nueva versión. Restaurar crea una nueva versión con el contenido de la versión base de origen y el registro de restauración; actualizar a una base más reciente es otra acción explícita.
3. Llenar el documento tomando paciente, propietario, peso, etc. de sus registros existentes, con fecha y procedencia. Se congela la instantánea; cambiar después el peso o nombre no cambia un documento firmado.
4. Revisar contenido, campos requeridos, MVZ responsable y firmantes. El tutor firma lo que efectivamente vio. Cualquier cambio de datos, texto o versión tras la vista previa invalida esa aceptación y requiere revisar/firmar nuevamente.
5. Finalizar mediante operación idempotente del servidor. Verificar permisos vigentes, hash del contenido aprobado, firma y versión, generar/validar PDF e imágenes en almacenamiento privado; calcular hashes de bytes reales. Marcar firmado solo cuando los archivos finales estén confirmados. La hora de firma es del servidor y aparece en el PDF final.
6. Storage y Postgres no comparten una transacción: usar preparación/finalización y comprobantes para que una falla no deje un documento «firmado» sin PDF. Limpiar únicamente archivos temporales huérfanos, nunca artefactos finales. Prohibir `UPDATE`, `DELETE`, reemplazo y eliminación en cascada de documentos finales, valores, firmas y archivos para roles de aplicación. Un vínculo por ID sin estas protecciones no basta.
7. Aclaraciones o correcciones posteriores crean un documento/evento nuevo vinculado al anterior. Revocación crea un evento con fecha/autor/alcance; el original permanece intacto. Una imagen de firma y un hash ofrecen trazabilidad, no certificación automática de validez legal.

Las versiones base futuras no actualizan las copias clínicas ni los consentimientos firmados. Dos editores concurrentes deben aportar versión esperada; si cambió, revisar diferencias antes de crear otra versión.

## 7. Integración clínica y control farmacológico

El guardado vincula el documento con el expediente y registra los hechos revisados mediante una operación idempotente. Un peso alimenta el evento de peso existente y su curva. Vacunas/desparasitación se registran con la estructura actual, sin inventar esquema o intervalos. No se duplica un mismo hecho al guardar o firmar otra vez.

Una hoja quirúrgica/anestésica registra medicamentos mediante `medication_records`; la tabla de la hoja se construye con esos registros. Si el producto está verificado como controlado, la operación crea el movimiento del libro requerido, o bloquea la finalización cuando faltan los datos exigibles. Una clasificación desconocida se muestra como pendiente; nunca se convierte silenciosamente en «no controlado».

El folio corresponde al MVZ/perfil y receta identificados; no se genera un folio oficial. La regla de unicidad será por titular y tipo/autoridad cuando exista respaldo, no una restricción global arbitraria que mezcle folios de diferentes médicos.

Programación hospitalaria es distinta de administración. El mismo tratamiento puede generar receta, tarea y hoja clínica, pero solo su evento confirmado alimenta una salida/aplicación que corresponda. Preparar, emitir, dispensar y administrar son acciones distintas; sus tipos e idempotencia impiden contabilizar dos veces el producto. Descontar existencias por lote y conciliar entradas/saldos se integra con M8, sin alegar que ya existe un libro operativo completo.

Clasificación, retiros y reglas legales viven en fuentes versionadas con estado verificada/sin verificar, igual que M3. Los plazos de conservación pueden capturarse/configurarse, pero no reducir un mínimo normativo verificado. Los plazos históricos impresos en el PDF no se adoptan automáticamente como vigentes. Conservar un plazo no habilita borrado automático de originales.

## 8. Plantillas propuestas para revisar

Estas son vistas de estructura, no documentos legales aprobados ni código. Los espacios indican captura manual o vinculación con datos existentes. No llevan el membrete del PDF de referencia.

### A. Consentimiento general

[Membrete de la clínica] · [Fecha del servidor]

Paciente [vinculado] · Propietario/representante [vinculado y verificado por el usuario]
MVZ [nombre/cédula] · Procedimiento [captura]

Motivo y objetivo [MVZ] · Alternativas [MVZ] · Riesgos explicados [MVZ]
Preguntas del tutor y respuestas [captura] · Costos [opcional]

Aceptación del procedimiento descrito, oportunidad de preguntar y apartado de revocación [redacción original para revisión]. Aviso de privacidad [enlace y versión].
Firma del tutor [nueva captura] · Firma profesional [propia o autorización identificada].

### B. Sedación, anestesia y cirugía

Estructura A + procedimiento específico, valoración previa, estudios aportados o no realizados, riesgos individualizados, límites de autorización, preparación indicada por el MVZ y cuidados posteriores. Bloque opcional de participación docente redactado por clínica, revisado por el MVZ titular y con aceptación registrada cuando corresponda.

Información original propuesta: «El equipo le explicará el objetivo del procedimiento, las alternativas y los riesgos identificados para su animal. Las indicaciones de preparación y recuperación se registrarán para este caso. Puede hacer preguntas antes de decidir y comunicar su decisión al MVZ responsable mediante el apartado de revocación».

La clínica puede reemplazar este texto informativo y redactar sus propias indicaciones preoperatorias y de recuperación. Son contenido de la clínica, revisado por el MVZ para el caso; no recomendaciones verificadas automáticamente por VetDosis Pro. No incluir horas de ayuno, medicamentos o probabilidades precargadas por la app sin una fuente clínica verificada. Los bloques de identidad, firma, privacidad y revocación permanecen protegidos.

### C. Eutanasia

Identificación de paciente/tutor/MVZ · Motivo clínico · Concepto previo del MVZ (campo descriptivo, no diagnóstico inferido) · Alternativas explicadas · Método propuesto · Disposición del cuerpo · Costo · Decisión expresa del tutor · Revocación · Firmas · Privacidad.

Constatación de muerte: entrada posterior vinculada, con resultado, método de constatación indicado por el MVZ, ejecutor y hora del servidor. Nunca completar retroactivamente ni cambiar el consentimiento firmado; no exigir confirmar muerte antes de autorizar el procedimiento.

Destino del cuerpo y decisiones sobre muestras [sección separada, aceptación específica cuando corresponda]; sin autorización implícita ni método farmacológico sugerido.

### D. Alta anticipada

Paciente + hospitalización vinculada · Tutor + MVZ · Fecha/hora
Solicitud del tutor · Estado documentado por el MVZ · Riesgos explicados · Recomendaciones y seguimiento · Preguntas · Decisión/firma · Privacidad.

Firmar la solicitud no descarga automáticamente al paciente: el MVZ confirma la salida mediante el flujo M5 y queda trazabilidad de ambos actos.

### E. Ingreso hospitalario

Paciente/tutor/MVZ · Motivo · Alcance autorizado · Comunicación/contacto · Costos editables · Revocación · Firmas · Privacidad.

Enlace a hospitalización y plan de tratamiento; la firma no genera fármacos o horarios por sí sola.

### F. Historia clínica

Paciente/tutor · Fecha · MVZ · Motivo · Antecedentes · Alergias · SOAP · Peso con unidad/fecha · Prevención · Estudios · Plan.

Vinculada al expediente M4, sin convertir datos faltantes en hallazgos normales.

### G. Hoja quirúrgica y anestésica / valoración ASA-EKG

Paciente, peso fechado, cirujano, anestesista y MVZ responsable del caso como campos separados; cada acto conserva quién lo realizó. Procedimiento · Evaluación y ASA ingresada por MVZ [escala/fuente pendiente cuando no exista referencia verificada] · EKG/hallazgos y adjunto opcional · Etapas del procedimiento.

Tabla repetible: hora de observación · registro farmacológico vinculado · cantidad/unidad/vía · FC/FR/pulso/temperatura y otras constantes · observaciones · responsable.

No hay una lista independiente de fármacos: se visualizan los mismos registros de medicación/control. Las alertas de constantes solo se habilitan con límites verificados por especie/contexto.

### H. Hospitalización y control de tratamientos

Ficha de jaula M5 + tareas existentes · tabla horaria · observaciones tipadas · administración con usuario/hora real · incidencias y seguimiento.

No reemplaza la tabla ni las alarmas M5. El PDF es una instantánea del periodo seleccionado, no una autorización para administrar.

### I. Anexo de control Grupos I y II

Dos tipos separados. Encabezado profesional/período y datos de la unidad de producción. Columnas protegidas observadas en la referencia: receta, producto, registro del producto, presentación, lote, unidades, especie, identificación del animal, dosificación, duración del tratamiento y retiro.

El Grupo I contempla además clave de aprobación/autorización en el encabezado del PDF recibido. Los títulos, definiciones y vigencia final deben corroborarse antes de etiquetar la exportación como formato oficial vigente. Hasta entonces se ofrece como referencia «sin verificar». No copiar logos institucionales ni afirmar homologación.

## 9. Pruebas de aceptación propuestas

- Firmar un documento con versión 1, editar/copiar/restaurar la plantilla a versión 2 y verificar mismo texto, valores, bytes PDF, firma, hash, perfil y hora en el original.
- Cambiar nombre/peso del paciente, membrete, aviso o cédula después: el firmado no cambia.
- Rechazar edición/borrado de campos obligatorios o columnas oficiales mediante UI y llamadas directas; llenar sus valores sigue permitido.
- Rechazar modificación/borrado de documentos finales, valores, firmas y archivos privados, incluso por admin de clínica; una corrección se anexa.
- Clínica A no lee/edita IDs, PDFs o firmas de B; base global no expone documentos clínicos.
- Auxiliar completa un borrador asignado y no edita plantilla/emite/obtiene contactos o firmas ajenos. MVZ no responsable no modifica la plantilla de otro.
- Retirar una delegación bloquea la emisión posterior aunque el cliente conserve un permiso viejo; la receta emitida previamente conserva su prueba de autorización.
- Reintento/concurrencia no duplica versión, receta, evento de peso, tarea ni asiento controlado. La revocación concurrente a emisión se decide con autorización bajo bloqueo en servidor.
- Falla de subida, PDF incorrecto o hash manipulado no produce estado firmado. Previsualización anterior a un cambio no autoriza contenido nuevo.
- Hoja anestésica y libro de control usan el mismo registro de fármaco; datos faltantes/control desconocido se marcan y no se omiten silenciosamente.
- Pruebas PDF: textos largos, tablas multipágina, español/acentos, firma visible, campos congelados, sin membrete de terceros y sin datos de otra clínica.

## 10. Alcance cuya aprobación se solicita

El usuario aprobó la estructura anterior y precisó dos ajustes: eliminar la formulación «irrevocable» en favor del apartado de revocación; permitir contenido informativo/indicaciones propias y logo en PDF por clínica. Ambos están incorporados a esta especificación. No se necesita repetir la aprobación de la estructura para iniciar el trabajo local.

Orden aprobado por el usuario: fase 1 plantillas/documentos/firmas/PDF; fase 2 historia clínica y hoja quirúrgica; fase 3 junto con M6 recetas/medicación/control. Se guarda solo el número de identificación del firmante, sin fotografía de su documento. La firma es una imagen distinta de la identificación. El PDF final se genera en servidor, se revisa después de capturar firmas y se finalizan los mismos bytes mediante su hash; no se regenera al confirmar. El estado de revisión de la plantilla es distinto de aceptación/firma del documento. Revisar antes de emisión oficial la fuente normativa y antes de alertas/cálculos las fuentes clínicas.

No se requiere ahora contraseña, clave de servicio, datos clínicos adicionales ni prueba desde el celular. La prueba real y aplicación remota continúan pendientes para el final, como pidió el usuario.
