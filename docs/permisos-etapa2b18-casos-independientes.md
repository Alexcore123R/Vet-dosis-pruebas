# Casos clínicos independientes del PDF

Candidato local **13L**, después de 13K. Sin aplicar a Supabase, sin APK ni apertura de beta.

## Estado y decisión de esquema

- **Implementado y probado previamente:** pantallas de casos existentes 13K, documentos y firmas 13J4, autoridad clínica tipada 13C.
- **Preparado localmente en esta ronda:** registro explícito del contexto de un caso sin generar un documento; selección del MVZ y conexión posterior con el flujo firmado.
- **Aplicado en remoto y probado:** ninguna migración o función de esta ronda. Las pruebas de GitHub usan PostgreSQL aislado.
- **Pendiente:** constatación de muerte y demás dependencias transversales, revisión/despliegue conjunto y pruebas reales de Auth/Storage/Edge y dos clínicas antes de abrir beta.

Se concreta el objetivo autorizado de crear casos sin exigir PDF: `clinical_cases.document_id` pasa a opcional, conservando la unicidad y FK cuando tiene valor. Los casos históricos no se actualizan ni se desligan de sus originales. Una hoja posterior se relaciona por su snapshot firmado 13J4; no sobrescribe el campo original del caso. Flutter admite la ausencia de documento y no intenta abrir un PDF inexistente.

El registro es **contexto**, no una atestación de atención. Elegir al MVZ no registra su aceptación, una firma, una consulta realizada ni su autorización individual. No se inserta una asignación de equipo clínico por el hecho de seleccionarlo. El MVZ solo autoriza actos/documentos mediante sus acciones explícitas existentes, con permisos y habilitación vigentes. El riesgo principal es confundir preparación administrativa con atención o aprobación; los flujos permanecen separados.

## Permiso y trazabilidad

Nuevo permiso `clinical.case.prepare`, no profesional y sin concesiones automáticas. El puesto visual no lo otorga. Registrar exige ese permiso vigente, lectura clínica y de pacientes, pertenencia actual y escritura permitida por beta. El paciente debe pertenecer a la misma clínica.

El MVZ se elige expresamente entre perfiles habilitados de la clínica con `clinical.authorize` y lectura clínica/paciente vigentes. No se elige una firma guardada ni se convierte un puesto en habilitación. La elección delimita quién podrá configurar/autorizar ese caso después; no concede a quien registra facultades de atención, recetas o controlados.

`private.clinical_case_intakes` conserva quién registró, su concesión/pertenencia, MVZ seleccionado, concesión/pertenencia/perfil del seleccionado, hash de la entrada y hora del servidor. Es privada y anexa; no expone firmas ni permite acceso directo a usuarios/servicio. La bitácora identifica el acto como registro de contexto, sin atención o autorización creadas.

## Datos y captura flexible

Datos mínimos: paciente, MVZ seleccionado, contexto (atención clínica/cirugía/evaluación prequirúrgica), fecha clínica y motivo. Notas opcionales. El tipo describe el contexto del caso, **no que una cirugía u otro procedimiento se haya realizado**. El título se toma del motivo capturado; no se inventa una conclusión.

Paciente, MVZ, contexto y fecha parten sin selección automática. La fecha se elige en calendario, sin hora, y el servidor rechaza fechas inválidas o futuras. No se exige PDF, firma, SOAP, peso, temperatura ni otros signos para registrar el contexto. No se rellenan antecedentes, ASA, EKG ni mediciones como normales. Las claves ajenas al contexto se rechazan; mediciones y actos se registran posteriormente por sus rutas propias.

En una pantalla abierta para un paciente concreto, el selector se limita a ese paciente. Registrar se protege contra apertura duplicada de la pantalla; guardar usa la operación idempotente del formulario y el servidor serializa por clínica/identidades. Un reintento simultáneo crea un solo caso. La autoridad se comprueba después de esperar el bloqueo y antes de reutilizar una operación anterior.

## Contrato e integración

Se conserva `clinical_workspace` versión 1 y se añade la capacidad versionada `registration_version=1`, acción `create`, pacientes y responsables elegibles. Flutter solo presenta el registro cuando reconoce esa versión y el repositorio lo soporta. Perder una capacidad conocida o recibir otra versión limpia datos/capacidades y no habilita la ruta antigua. La capacidad de registrar no habilita observar, actuar, autorizar o emitir.

Los documentos vinculados firmados siguen listándose por separado; `is_original` es explícitamente falso si el caso no tiene original. La lectura no crea un documento ni obliga a generar uno. Se prueba el recorrido completo: registrar contexto sin PDF, configurar y autorizar explícitamente un ámbito, elaborar/firmar/revisar la hoja por las cuentas correspondientes, emitirla y abrir sus bytes originales desde el caso. El caso conserva `document_id=null` y no aparecen mediciones ni actos automáticos.

La prueba de frontera del artefacto usa encabezado PDF/PNG sintético; no acredita una ejecución real de Edge. El renderer real y la conservación del PDF se validaron en 13J4 y siguen en el workflow de regresiones. No se importan datos clínicos, dosis, calendarios ni normas nuevas.

## Validación reproducible

- `bash supabase/tests/run_independent_clinical_cases.sh`: dependencias completas, datos ficticios, permisos actuales, fechas, campos de contexto, paciente/clínica, ausencia de efectos clínicos, trazabilidad, documento posterior y concurrencia/vencimiento tras bloqueo.
- `test/independent_clinical_cases_test.dart`: capacidad versionada, selección manual, ausencia de datos clínicos prellenados, permiso independiente del puesto y calendario sin normalizar fechas inválidas.
- Análisis y batería Flutter completa; el workflow manual añade `independent-clinical-cases` sin secretos de servicio, despliegue ni APK.

Validación local: **339 pruebas Flutter correctas**, incluidas las 5 nuevas de registro/calendario; análisis sin incidencias. PostgreSQL aislado, recorrido de hoja posterior y pruebas de concurrencia/vencimiento correctos. El enlace de GitHub se registra al cerrar la ejecución.
