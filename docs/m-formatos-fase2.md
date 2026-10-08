# M-FORMATOS — fase 2, implementación local

Preparada el 7 de octubre de 2026. Reutiliza las tablas, versionado, aprobación, firmas y generación de PDF de la fase 1. No se sustituyeron pacientes, propietarios, membresías ni hospitalización. No se aplicó SQL ni se desplegó la función en el proyecto remoto.

## Uso

En **Formatos**, copiar una base de historia clínica, hoja quirúrgica/anestésica o valoración prequirúrgica. Revisar la copia y aprobarla para uso clínico. Un MVZ crea el borrador, puede asignarlo a un auxiliar, captura su firma, revisa el PDF completo y confirma. Los documentos clínicos requieren firma del MVZ, sin firma ni identificación del tutor: no son consentimientos. La autorización quirúrgica sigue siendo un consentimiento aparte; puede vincularse si está firmada, corresponde al mismo paciente y clínica y es accesible al responsable.

El panel **Casos clínicos, mediciones y actuaciones** muestra los casos disponibles. También se abre desde el paciente. El SOAP y peso inicial se incorporan atómicamente a `vet_patient_events` al confirmar el documento; no se duplican al reintentar. Las mediciones posteriores de peso alimentan la misma curva. Alergias y prevención siguen en M4, sin otra base paralela.

La hoja quirúrgica separa cirujano, anestesista y responsable del caso; una misma persona puede desempeñar más de un papel, pero las asignaciones permanecen separadas. Los profesionales asignados se eligen entre miembros MVZ actuales de la clínica. Se muestran etiquetas internas de cuenta y UUID; la captura del nombre/cédula del responsable sigue explícita hasta integrar perfiles profesionales con M6.

ASA y EKG son texto registrado por el profesional. No hay clasificación automática, interpretación, rangos fisiológicos, dosis ni protocolos precargados. Cada medición conserva decimal exacto, unidad, hora observada, persona que la realizó, quien la capturó y fecha/hora del servidor. Una falta de captura no equivale a un valor normal. Las fechas de observación se capturan en UTC con segundos; la app propone la hora actual para nuevas entradas y la original para correcciones.

## PDF y registros posteriores

El PDF se genera en la Edge Function `forms-pdf`, con los datos, versión, membrete y firma profesional de la instantánea preparada por el servidor. El visor presenta esos bytes y su hash verificado. La finalización exige misma revisión y SHA-256; guarda el artefacto original, sin regenerarlo después de firmar. En la misma transacción crea el caso, asignaciones y hechos iniciales. Si falla una validación o creación de hechos, tampoco finaliza el documento.

El PDF original representa la hoja firmada en ese momento. Actuaciones, mediciones y correcciones posteriores pertenecen a la cronología del caso y **no se agregan retroactivamente al PDF original**. Toda corrección de medición se anexa con referencia y motivo por el MVZ responsable; el original permanece visible como sustituido. La curva de peso excluye el evento sustituido y utiliza su corrección, sin modificar ninguna fila histórica. Las notas posteriores de actuación no se borran ni se editan; se añade otra entrada explicativa.

No se incorporó una captura farmacológica duplicada en la hoja: las indicaciones actuales siguen en Hospitalización. El vínculo estructurado de actos/medicación, frascos, receta y registro de controlados queda para la fase 3/M6. Tampoco se generan rangos o alertas clínicas sin referencias verificadas.

## Autorizaciones por persona

El responsable MVZ puede conceder un procedimiento concreto a un miembro MVZ/auxiliar del caso, con vencimiento, o revocarlo con motivo. Los permisos son registros anexos y no se sobrescriben. Se revalida la hora actual del servidor para capturar y la vigencia al momento observado para atribuir un acto a otra persona. Un auxiliar solo reporta actos propios. No se permite atribuir retrospectivamente un acto anterior al otorgamiento del permiso. El MVZ puede registrar un acto realizado por otra persona elegible, conservando los dos autores.

Admin consulta los casos de su clínica, pero el rol administrativo por sí solo no permite emisión clínica, actuaciones ni otorgar permisos. MVZ responsable y MVZ asignados consultan el caso; otros MVZ solo lo ven si reciben autorización vigente. Auxiliar autorizado ve el caso, sus anexos y el documento clínico original, sin abrir otros consentimientos ni datos generales del propietario. La revocación/expiración retira lectura y captura de quien dependía de esa autorización. Recepción/estilista y otra clínica no acceden.

Los eventos M4 ligados a estas hojas usan la autorización del caso. No se amplía el acceso a todos los SOAP/pesos por estar en M4. RLS y RPC validan permisos; no hay escritura directa de clientes. El cambio de identidad/clínica elimina las rutas privadas, los modelos limpian datos tras errores y al destruirse, y no hay almacenamiento sensible offline.

Los permisos de procedimientos **no habilitan recetas, dispensación cuantificada, validación farmacológica ni reportes oficiales**. Esas operaciones se implementarán con sus validaciones propias en M6.

## Constatación posterior a eutanasia

En un consentimiento de eutanasia firmado, abrir **Constatación posterior / correcciones**. Solo el MVZ responsable puede anexar resultado confirmado/no confirmado, método empleado, hallazgos y hora observada, que debe ser posterior a la aceptación y no futura. Se conserva autor/hora del servidor. Disposición realizada y costo posterior se capturan aparte de los acuerdos originales; no se inventan ni sustituyen esos acuerdos.

La corrección enlaza una entrada anterior del mismo consentimiento y exige motivo. No hay fotos de identificación del tutor. No se modifica el consentimiento/PDF ni se cambia automáticamente el estado del paciente o su hospitalización. El MVZ debe revisar esas operaciones por separado.

## Esquema y despliegue

Aplicar una vez `supabase/adaptations/existing_forms_phase2.sql` **después de M2, M4 y fase 1**. M3/M5 no son dependencias de esta adaptación. Desplegar la versión actualizada de `forms-pdf` junto con ella antes de usar hojas clínicas.

Tablas nuevas: `clinical_cases`, `case_staff_assignments`, `clinical_observations`, `clinical_procedure_acts`, `person_procedure_authorizations`, `person_procedure_revocations`, `clinical_death_records`. Todas conservan historia mediante inserciones; triggers impiden actualización/borrado incluso con acceso privilegiado ordinario. FKs compuestas validan paciente/documento por clínica. Se añaden a M4 referencias opcionales `form_document_id`, `clinical_case_id`, `clinical_observation_id`; los eventos anteriores conservan sus permisos.

Bases originales: `assets/clinical/forms.clinical.v1.json`, versión 1, fuente estructural original y estado **sin verificar**. Aprobación de clínica y verificación de referencia son conceptos distintos. No se copió texto/decoración de PDFs de terceros. La estructura no constituye validación normativa de un formato oficial.

## Verificación y pendientes

- `bash supabase/tests/run.sh clinical`: PostgreSQL local aislado y datos sintéticos; incluye la suite de fase 1, SOAP/peso atómicos e idempotentes, asignaciones separadas, permisos por persona/procedimiento, revocación, unidades, conservación de PDF, corrección de peso sin duplicarlo en curva, eutanasia posterior/corrección y aislamiento por clínica. Los artefactos binarios del test SQL son ficticios; el renderizador se prueba con PDFs reales aparte.
- Flutter: suite total de 74 pruebas; validación de plantillas/fechas/unidades, ausencia de datos clínicos por defecto, limpieza de modelos y vista de teléfono con firma profesional únicamente, más las pruebas anteriores.
- Generador real: cinco pruebas; hoja clínica con los profesionales asignados, datos y firma del MVZ; las pruebas de consentimientos, imágenes y PDF multipágina siguen incluidas.
- Análisis Flutter, tipado Deno y compilación web configurada.

Pendientes: instalación/pruebas con usuarios reales en Supabase, impresión/compartir en Android/iPhone, validación de textos de clínica, modo offline clínico y revisión con datos reales. Los perfiles, firmas compartidas y enlaces de medicación/hospitalización ya tienen implementación local en [M6](m6-recetas-control.md). Las pruebas locales no acreditan funcionamiento remoto ni vigencia jurídica.
