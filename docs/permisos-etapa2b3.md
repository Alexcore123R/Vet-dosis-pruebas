# Propuesta 2B-3: expediente y actuaciones clínicas

Estado: candidato SQL probado, aprobado por la propietaria para incorporarlo al corte coordinado; no desplegado. La aprobación se recibió en esta conversación después de presentar la propuesta 13C y su restricción conservadora de actos. No autoriza desplegar este archivo aisladamente, publicar un APK ni abrir beta. No acredita el fin de la migración clínica.

## Esquema para revisión

| Cambio | Finalidad |
| --- | --- |
| Código `clinical.read` | Separar la lectura clínica del registro/lectura administrativa de pacientes; la consulta exige además `patient.read` |
| Código `clinical.authorize` | Autorizar configuración y concesiones del caso; exige evidencia profesional vigente y ser responsable de ese caso, además de la concesión explícita |
| `private.clinical_scope_bindings` | Relacionar caso y alcance técnico existente con un tipo de procedimiento de esa clínica, condición profesional, referencia de política, autor y hora |
| `private.clinical_scope_revocations` | Sustituir la relación mediante registros anexados; no borrar ni sobrescribir decisiones anteriores |
| Tres columnas en `person_procedure_authorizations` | Conservar qué concesión autorizó al responsable y con qué relación de alcance y membresía se concedió la autorización del caso |
| Bloqueo de identidad profesional | Serializar actuaciones con nuevas revisiones, revocaciones e identidad capturada, sin privilegios nuevos para el cliente |

Las autorizaciones históricas conservan sus campos nuevos en NULL y no habilitan actos en el nuevo modelo. No se convierten roles, asignaciones, puestos ni cédulas capturadas en evidencia verificada. No se crean tipos, relaciones, concesiones o verificaciones reales de ejemplo.

### Restricción conservadora propuesta para la beta

En este candidato todos los alcances de actos requieren habilitación profesional. Solo el alcance técnico de observaciones admite una política que permita captura sin habilitación, si el responsable habilitado y con permiso explícito la configura para el tipo concreto. Por defecto la condición profesional es verdadera; no se deduce del nombre del procedimiento ni de su puesto.

Esta es una restricción de acceso propuesta para el piloto, no una declaración de qué actos reserva la legislación ni una tabla clínica validada. Excepciones adicionales requieren su propia revisión, no un cambio libre de nombre. La referencia aportada por el responsable se registra; la app no la certifica jurídicamente.

## Comportamiento del candidato

- `clinical_cases_list`, `clinical_case_snapshot` y las RLS que usan `clinical_readable` exigen lectura clínica y administrativa explícitas. Un admin o una persona asignada al caso no obtiene acceso por ese motivo.
- Registrar observaciones o actos requiere simultáneamente: lectura autorizada, relación de alcance vigente, permiso `procedure.perform` del tipo exacto, autorización explícita para ese caso y, cuando corresponda, habilitación verificada vigente tanto ahora como en la fecha observada. El registro debe ser posterior a la relación y a la concesión; no autoriza retrospectivamente actuaciones antiguas.
- El autor solo registra su propia actuación. Reportar una actuación ajena necesita un flujo diferenciado todavía no incluido; no se permite fingir la identidad del ejecutante.
- La auditoría identifica concesión, relación y procedimiento utilizados. El autor y las horas de servidor originales se conservan. Se comprueba autoridad antes de devolver recibos de reintento.
- Una corrección de medición exige responsable habilitado con permiso de autorización, motivo y permiso de actuación. Se anexa, manteniendo el valor y autor del original. El timeline mantiene el filtro previo para valores sustituidos.
- Configurar el alcance exige responsable del caso, lectura y `clinical.authorize`. Repetir exactamente la misma configuración devuelve su ID sin invalidar autorizaciones. Cambiarla anexa la sustitución y requiere autorizar de nuevo el caso bajo la relación nueva.
- Las autorizaciones por caso se crean/revocan sin atajos de rol, bajo el permiso profesional correspondiente. Quedan ligadas a la fecha de membresía: salir y reingresar no reactiva la autorización del caso.
- La ruta libre `add_vet_patient_event` queda cerrada en el candidato: no posee un tipo de procedimiento estructurado y no se le atribuye uno automáticamente. SOAP, alergias, preventivos y consentimientos de esa ruta requieren un flujo adaptado antes de desplegar. Sus registros históricos no se alteran.

Los alcances técnicos provienen del esquema existente. No se copian dosis, normas, retiros ni referencias clínicas del prototipo.

## Concurrencia

Se mantiene el orden de bloqueo clínica → caso → persona cuando corresponde. Un bloqueo transaccional de identidad de la persona coordina la evaluación con las inserciones de evidencia, revocaciones y versiones de perfil. La revisión externa conserva los controles de plataforma separada; el nuevo bloqueo no habilita al usuario a revisar a nadie.

Las comprobaciones usan el tiempo actual tras esperar y vuelven a comprobar la identidad revisada. Revocar evidencia no borra registros ni cambia PDF históricos. Las pruebas incluyen una revocación profesional no confirmada que toma primero el bloqueo: la operación clínica espera y, tras confirmar la revocación, debe ser rechazada.

## Límites y pasos restantes

No desplegar este archivo solo: modifica helpers usados por formularios, recetas y medicación, que también necesitan su corte y pruebas. `rx_professional`, permisos específicos de administrar/extracción, emisión de recetas, formatos, constatación de muerte/eutanasia, PDF, Storage, Edge Functions, exportaciones y consultas agregadas independientes siguen pendientes. El cierre de `add_vet_patient_event` es deliberadamente restrictivo; falta adaptar su captura, no se presenta como sustitución funcional completa.

La pantalla clínica aún no incorpora el selector/configurador de relaciones ni todas las nuevas facultades. El catálogo genérico de administración podrá enumerar los códigos, pero eso no constituye integración completa de la UI. La base actual del servidor sigue sin este candidato y la beta continúa cerrada.

## Validación

`bash supabase/tests/run_permission_clinical.sh` reconstruye en PostgreSQL Docker aislado las dependencias reales de planes, agenda, expedientes y permisos. Solo usa identidades, evidencia, mediciones y políticas sintéticas.

Casos: admin sin lectura denegado; MVZ sin evidencia no obtiene autoridad; profesional verificado sin concesión bloqueado; permiso de procedimiento B no habilita A; lectura separada; observación propia con relación explícita; reintento sin duplicado; prohibición de atribución ajena; ruta libre bloqueada; trazabilidad de concesión/relación; histórico inmutable y corrección anexada; autorización antigua sin metadatos no sustituye una nueva; exigencia profesional de la política; revocación profesional; aislamiento y anon. Caso concurrente: revocación que toma primero el bloqueo impide la autoridad clínica que esperaba.

Resultado SQL local satisfactorio, incluida revocación profesional concurrente y no reactivación de la autorización del caso tras reingresar con permisos operativos nuevos. GitHub: [ejecución 38869137594](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38869137594), commit `b1e745e`, satisfactoria en los tres trabajos de pacientes, agenda y expediente. Solo PostgreSQL aislado, sin secretos ni conexión al Supabase remoto.

No hay cambios Flutter en este bloque: las 264 pruebas previas no se presentan como validación de una UI clínica nueva. La ampliación de esquema y la restricción conservadora de actos quedaron aprobadas para el corte coordinado. Continúan pendientes la integración de UI, captura estructurada, módulos dependientes y pruebas Auth reales antes de preparar ese despliegue.
