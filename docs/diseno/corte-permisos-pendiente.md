# Corte de autorizaciones: inventario inicial posterior a 2A

16-oct-2026. Lista de integración pendiente, no cobertura implementada. La base desplegada se describe en [etapa 2A](../permisos-etapa2a.md). No activar admisiones a partir de este documento.

| Área | Rutas/dependencias encontradas | Condición del corte |
|---|---|---|
| Pacientes | `create_vet_patient`, `add_vet_patient_event`, políticas de pacientes/tutores/eventos | Separar altas y datos administrativos de anotaciones clínicas; sustituir roles por permisos explícitos y conservar clínica/paciente del evento. No asumir que `patient.write` autoriza cualquier acto clínico. |
| Agenda | `ops_patient_search`, funciones de citas y políticas de lectura; `ops_dashboard`, `att_dashboard` | Aplicar lectura/gestión de agenda por persona; revisar las respuestas agregadas para no filtrar áreas sin permiso. |
| Hospitalización | `hospital_admit`, `hospital_prescribe`, `hospital_task_action`, `hospital_discharge`, políticas de estancias/tareas | Revisar prescripción, confirmación, observación, posposición y alta por acción. `hospital_task_action` está redefinida en M6: modificar la versión final, no solo el script M5. |
| Aplicaciones y frascos | `rx_medication_report`, `rx_medication_review`, `rx_vial_open/close/adjust`, `rx_schedule` | Procedimiento explícito y concesión usados en el registro; comprobar producto, frasco, lote, paciente, clínica e identidad real del ejecutante. Bloquear controlados para ajustes libres y facultades reservadas. |
| Recetas | `private.rx_professional`, `private.rx_permission`, `private.rx_prepared_permission`, `rx_prepare`, `rx_finalize`, generación/registro PDF | Sustituir habilitación heredada, preparación/autoridad separadas y confirmación del responsable. Revisión al preparar y al emitir; probar revocación entre ambas. La autorización permanente se declara como acto previo, no como revisión individual ficticia. |
| Formatos y expediente clínico | `private.clinical_eligible`, `private.clinical_write_check`, `private.form_readable`, `private.form_professional_check` y funciones redefinidas por M6 | Preservar autoría y versiones; firma del tutor propia; no imprimir título/cédula sin habilitación al emitir. Las correcciones se anexan. |
| Inventario y ventas | `private.inv_access`, `private.inv_dispense`, `inv_sale_post`, flujos de entrega/aplicación | Reemplazar acceso por persona, conservar movimientos y conflictos; dispensación sujeta a receta solo por MVZ habilitado. Ventas no se corrigen como existencias. Revisar la última redefinición de `inv_sale_post` en operaciones M9. |
| Respaldos y exportación | snapshot operativo, tablas/archivos incluidos y PDF congelados | Permiso más condición administrativa o responsable según el tipo de respaldo. Excluir evidencia privada y cuentas ajenas. No convertir `backup.export` por sí solo en autorización universal. |
| Storage | políticas sobre fotos, documentos, firmas y objetos de clínica | Permiso, dueño, clínica y estado de beta; probar lectura y mutación con Auth real. No confiar exclusivamente en ocultar opciones de la app. |
| Edge Functions | `forms-pdf`, AI/starter/billing y rutas de servicio | Comprobar sesión/ámbito en servidor y no usar privilegio de servicio como sustituto de la autorización del usuario. Conservar originales históricos. |
| Plataforma y MFA | hook `beta_request_guard`, revocación de habilitación global y RPC administrativos | La cuenta separada no se inscribe como usuaria clínica. Resolver y probar su ruta de revocación profesional bajo el hook activo, con comprobación de plataforma/MFA por operación. Los RPC `permission_*` no están exentos automáticamente. |
| UI y offline | navegación y acciones que aún consultan `ClinicRole` | Consumir estado efectivo de servidor; limpiar accesos al cambiar de usuario/clínica; no reutilizar facultades de la caché. La cola offline de aplicaciones debe reevaluar permisos y revocaciones al sincronizar. |

## Pruebas pendientes del corte

1. Matriz por acción con admin sin habilitación, puesto «MVZ» sin evidencia, profesional verificado sin permiso, permiso sin habilitación, responsable aceptado y persona de otra clínica.
2. Procedimiento A no autoriza B, ni administración autoriza extracción. La clase de acto reservado se comprueba además de la concesión operativa; no inferirla del nombre del procedimiento ni de un puesto.
3. Serialización de revocación frente a preparar/emitir/aplicar/extraer, sin guardar actos que usaron autoridad ya retirada. Guardar concesión, autor y hora del servidor; idempotencia de aplicaciones y movimientos.
4. HTTP real de RPC, tabla directa, Storage y Edge Functions con dos cuentas/dos clínicas, incluyendo anon, vencimiento y cambio de correo.
5. Preparación ordinaria con datos del MVZ → PDF → emisión: comprobar que preparador y acto de autorización quedan descritos correctamente, con snapshot y hash.
6. Solo marcar revisada la migración tras sustituir todas las rutas correspondientes. No agregar un OR con roles antiguos como compatibilidad. Mantener beta cerrada hasta completar el corte y sus pruebas.

## Avance 2B-1, 16-oct-2026

Se preparó y probó localmente el candidato de alta administrativa y lectura directa de pacientes/tutores: [detalle y límites](../permisos-etapa2b1.md). No está desplegado y no cubre eventos clínicos, agenda ni consultas agregadas. El corte completo de esta tabla continúa pendiente; no marcar la fila de pacientes como migrada en su totalidad.

## Avance 2B-2, 16-oct-2026

Candidato local de agenda y `ops_dashboard`: [detalle y límites](../permisos-etapa2b2.md). Se separaron `appointment.read`, `appointment.manage` y `patient.read`, sin desplegar. Los otros agregados operativos quedan vacíos en el candidato hasta mapear sus permisos. No acredita la migración de `att_dashboard`, estadísticas, hospitalización ni todas las áreas del dashboard.
