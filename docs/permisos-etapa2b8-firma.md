# 2B-8: nombre y firma de quien realizó la consulta

Decisión aprobada por la usuaria, 16-oct-2026. Implementación **parcial y local** 13H1, sin desplegar ni abrir beta.

## Preparado y probado en este bloque

- Candidato `supabase/proposed/13H1_consultation_attestation.sql`: firma inmutable de la persona autenticada, nombre capturado, hora del servidor, revisión/hash del borrador, época de membresía y concesión `prescription.prepare` usada. No acepta un usuario firmante suministrado por el cliente ni exige inventar una cédula al participante.
- La firma requiere confirmación explícita de haber realizado la consulta. Es una declaración de la persona, no prueba automática de que efectuó el acto ni concesión de permiso para realizarlo. Las restricciones clínicas de 13C se conservan; no se habilita una actuación clínica por firmar.
- `rx_consultation_sign` exige lectura de paciente/caso y permiso explícito; responsable profesional vigente. Para un documento marcado controlado, solo firma el responsable habilitado. No autoriza, emite, dispensa ni mueve existencias.
- Helper privado de consumo exige el mismo borrador, contenido y revisión, con miembro/concesión todavía vigentes. Los cambios de indicaciones invalidan el uso pendiente. No se prestan firmas del perfil ni se convierten históricos.
- Contrato nuevo del renderer: `prescription_identity_version: 1`, con `prescription_identity` separado en `consultation`, `prepared_by`, `responsible`, `authorization` y `controlled`. La firma obligatoria proviene exclusivamente de `consultation.signature`; no se completa con `mvz_signature` heredada.
- PDF con «Consulta realizada por», «Firma de quien realizó la consulta», datos del responsable separados y «Documento elaborado por» solo si lo capturó otra persona. No añade puesto ni cédula del responsable al firmante de la consulta.
- Distingue autorización individual de previa; la previa no afirma revisión individual. El contrato inicial solo admite autorización previa por caso/tipo ordinario. Esta limitación técnica no decide por la usuaria una ampliación a toda la clínica.
- Validación de nombres coherentes por cuenta, referencias, fechas y ámbito del contrato. Para controlados, se rechaza modalidad permanente o firmante distinto del responsable. El servidor debe comprobar la verificación real: un campo del snapshot no la acredita.

## Contrato de datos para conectar el siguiente bloque

`consultation` lleva `user_id`, `name`, `attestation_id`, `signed_at` UTC y `signature`; el servidor los obtiene de la atestación privada seleccionada explícitamente. Nunca aceptar esa identidad/imagen como prueba desde un snapshot enviado libremente por el cliente.

`responsible` lleva `user_id`, `name`, `license` y `profile_version_id` de la versión habilitada. `prepared_by` lleva la cuenta/nombre de quien preparó realmente. Si una misma cuenta ocupa varias participaciones, su nombre debe ser coherente.

`authorization` lleva `mode`, `actor_id` del responsable, `authorized_at`, `reference_id`; en modalidad previa, también `document_type='ordinary_prescription'`, `case_id` coincidente y `valid_until`. `prepared_at` del snapshot representa el momento del servidor en que se congela ese contenido para PDF; no puede anteceder a su firma/autorización. Las fechas del contrato son ISO UTC con `Z`.

El transporte histórico del artefacto llama `mvzPng` a la imagen guardada; para este contrato contiene la firma de quien realizó la consulta y también se devuelve como `consultationPng`. El nombre de transporte no define su habilitación. La conexión pendiente de `rx_pdf_register` debe vincular el artefacto con la atestación y el hash del snapshot.

## Pendiente, sin afirmar que está implementado

1. Conectar selección/captura de firma en Flutter. Si una persona solo captura para otra, la segunda debe firmar desde su propia sesión; no habilitar «firmar por» mediante un selector.
2. Sustituir conjuntamente `rx_prepare`, autorización, `rx_finalize` y registro/lectura PDF, incluyendo permisos/delegaciones. **Las rutas actuales aún no llaman al helper nuevo**: este bloque por sí solo no impone el requisito en la app instalada ni completa el corte de recetas.
3. Hacer obligatorio el contrato nuevo para documentos nuevos al aplicar el corte coordinado. Los snapshots antiguos sin marcador mantienen el renderer histórico; esto conserva compatibilidad, no autoriza crear recetas nuevas por una ruta heredada después del corte.
4. Bloquear dispensación y demás rutas reservadas con permisos/habilitación efectivos. Este registro de firma no prueba esa migración.
5. Pruebas integrales de autorización individual/permanente, HTTP, Edge y teléfono; revisión de los requisitos del formato. No declarar el documento normativamente válido por superar pruebas de software.

## Verificación

Ejecutar `bash supabase/tests/run_consultation_attestation.sh` en PostgreSQL aislado y `npm run test:renderer` desde `supabase/`. El primero incluye dependencias/fixture sintéticos, privacidad, firma propia sin perfil profesional, duplicados, contenido/revisión obsoletos, controlados, revocación y carreras; el segundo extrae texto de PDF real y compara las imágenes de firma.

Resultado local de este bloque: PostgreSQL y carreras satisfactorios; **15 pruebas del renderer satisfactorias**. No se modificó Flutter ni se atribuye a este cambio una nueva ejecución de sus 284 pruebas previas. Se añadieron trabajos de firma y PDF al workflow manual `test-permission-cutover.yml`, sin secretos de servicio ni despliegue.

GitHub confirmó **nueve trabajos satisfactorios** sobre `125fd46`: [run 38950491414](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38950491414). Incluye los siete bloques previos, `consultation-signature` y `prescription-pdf`. Esta evidencia prueba el candidato/renderer en aislamiento; no implica aplicación remota ni integración de Flutter.

No se modifican tablas remotas, habilitaciones reales, datos clínicos ni el APK instalado.
