# Pantallas clínicas con acciones explícitas y documentos vinculados

Candidato local **13K**, después de 13J4. No desplegado a Supabase, sin APK ni apertura de beta.

## Estado, fases y decisiones

- **Implementado y probado previamente:** firma propia de elaboración/atención, autorización individual, tutor y PDF en 13J4; autoridad clínica tipada en 13C.
- **Preparado localmente en esta ronda:** contrato de lectura por caso e interfaz para usar las acciones efectivas, configurar correspondencias de procedimientos y consultar documentos firmados vinculados.
- **Aplicado en remoto y probado:** ninguna migración ni función de esta ronda. GitHub solo prueba bases aisladas.
- **Pendiente:** crear casos independientes del PDF, revisar/adaptar constatación de muerte y otras rutas transversales, y pruebas reales de Auth/Storage/Edge antes de desplegar el corte conjunto.

Fase implementada: reemplazar botones y selectores por puesto cuando existe el contrato válido; conectar la lectura de documentos nuevos al caso existente; probar pérdidas de autoridad y compatibilidad. El riesgo principal es mostrar una facultad que la cuenta no tiene o llamar firmado a un documento pendiente. El servidor sigue validando cada escritura por sus RPC tipadas, aunque la pantalla se haya quedado desactualizada.

Esta ronda **no cambia el esquema de casos**, no crea permisos nuevos ni convierte registros históricos. La separación de la creación de un caso respecto del `document_id` obligatorio actual se deja para una propuesta de esquema posterior: no se crean consultas automáticamente al emitir un formato ni se genera un PDF ficticio para sortear esa relación.

## Contrato por caso

`clinical_workspace(clinic, case?)`, `schema_version=1`, `mode=explicit_clinical`:

- Lectura clínica/paciente actual y misma clínica; no depende de puesto visual.
- Acciones independientes: observar, anexar actuación, corregir medición, autorizar en el caso, revocar y configurar correspondencia con tipo de procedimiento.
- Observación y actuación requieren elegibilidad vigente de la **cuenta actual** en su ámbito. La autorización del caso por sí sola no concede permiso operativo ni habilitación profesional.
- Corrección requiere autoridad actual del responsable y permiso propio de mediciones. Configuración/autorización/revocación requieren el responsable habilitado con `clinical.authorize`; no se habilitan por el rótulo MVZ.
- Ámbitos de actuación, correspondencias vigentes y opciones de miembros/procedimientos configurados. No concede permisos al consultar esas opciones.
- En modo beta de solo consulta/exportación no se anuncian acciones de escritura. La elegibilidad se vuelve a comprobar al guardar por los controles existentes.

La configuración usa `clinical_scope_bind` existente: elección explícita del ámbito y tipo configurado, política profesional, fuente y motivo. Conserva las restricciones profesionales de 13C. Autorizar a alguien exige elegir persona, ámbito y vencimiento; no hay un vencimiento prellenado ni concesión automática de permisos de receta/controlados.

## Captura anexa e interfaz

La ruta nueva no consulta la lista antigua de personal por roles. En mediciones/actuaciones se fija `performed_by` a la cuenta actual; no hay selector para atribuirlas a otra persona. El servidor ya rechaza esa atribución con `own_act_only`.

No hay preselección de medición, ámbito ni hora. La medición elegida muestra su unidad. Solo se pide el valor de la medición que se decide registrar; no se exigen otros signos, peso, temperatura ni SOAP. Las notas de una medición son opcionales; una actuación sí necesita su descripción. Corregir conserva el registro original y exige motivo y una entrada anexa.

Flutter valida versión, ámbito del contrato, tipos de acciones/opciones y documentos firmados. Una respuesta desconocida o pérdida de un contrato conocido limpia los datos/capacidades; no vuelve a autorización por puesto. El acceso desde Formatos también usa lectura explícita cuando conoce el contrato, sin barrera por puesto. Antes de abrir una captura vuelve a consultar el caso. Las respuestas tardías de una pantalla cerrada o una consulta anterior no restauran datos.

En un servidor anterior que aún no tiene este RPC se conserva la interfaz anterior; esa compatibilidad solo se admite antes de conocer el contrato. El candidato no se despliega para activar permisos mientras queden rutas antiguas pendientes.

## Documentos y límites

La pantalla consulta por separado los documentos **ya firmados** relacionados con el caso, su paciente y clínica y legibles para la cuenta: original histórico, consentimiento vinculado y documentos 13J4 cuyo snapshot refiere al caso. Muestra cada uno con su título y abre su PDF original por la ruta de acceso vigente. No presume que el `document_id` histórico está firmado; un borrador no se ofrece como PDF firmado.

Consultar el contrato o abrir una hoja no publica casos, observaciones, notas SOAP ni actuaciones. Esta fase adapta **casos existentes**; no resuelve aún el arranque de un caso nuevo con el esquema desacoplado del PDF. El mensaje de pantalla deja de indicar que confirmar un formato crea una consulta.

Los fixtures SQL insertan metadatos firmados sintéticos para probar el vínculo de lectura; no acreditan una emisión o firma nueva real. La generación/retención del PDF se prueba por separado en 13J4. No se agregan valores clínicos, dosis ni normas.

## Validación

`bash supabase/tests/run_clinical_screen_contract.sh` aplica todas las dependencias hasta 13J4 en PostgreSQL aislado y prueba autoridad explícita, puesto sin facultades, habilitación revocada, observación propia, lectura entre clínicas y documentos vinculados sin publicar datos clínicos.

`test/clinical_screen_contract_test.dart` prueba lectura denegada sin consultar filas, contrato perdido/desconocido, permiso independiente del puesto, ausencia de atribución ajena y documentos firmados separados del original. Se ejecutan además las regresiones clínicas, análisis y batería Flutter completa. El workflow manual incorpora el trabajo `clinical-screen-contract` sin despliegue.

Validación local: **334 pruebas Flutter correctas**, análisis sin incidencias y **15 pruebas enfocadas** correctas (6 nuevas y regresiones clínicas/borradores). PostgreSQL aislado correcto. GitHub Actions: [ejecución 38981534052](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38981534052), commit de código `52fe855`: **18/18 trabajos correctos**, incluido `clinical-screen-contract`, sin despliegue ni APK.
