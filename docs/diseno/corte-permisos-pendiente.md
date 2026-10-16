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

## Avance 2B-3, 16-oct-2026

Candidato de expediente/actuaciones y propuesta de relación explícita de alcance a tipo de procedimiento: [esquema, restricción conservadora y límites](../permisos-etapa2b3.md). No desplegado. La autorización clínica histórica se conserva sin convertirse al nuevo modelo. La captura libre y la integración de UI/formularios/medicación siguen pendientes; no marcar terminado el corte clínico.

## Avance 2B-4, 16-oct-2026

Ingreso sin jaula y cambios de ubicación auditados: [candidato 13D y evidencia](../hospitalizacion-captura-flexible.md). SQL/UI preparados; no desplegados. No equivale a autorización de medicación ni a migración completa de navegación por permisos.

## Avance 2B-5, 16-oct-2026

Revisiones hospitalarias ligadas a tipo de procedimiento: [candidato 13E y límites](../permisos-etapa2b5.md). Se separan programación, posposición y confirmación con permisos explícitos; las revisiones históricas no reciben autoridad automática y la ruta genérica de medicación queda cerrada. Selector y controles por acción preparados en la UI; navegación completa, reautorización histórica, alta, `rx_schedule`, aplicaciones/frascos y validación siguen pendientes. No desplegar 13E aisladamente ni declarar terminado el corte hospitalario.

## Avance 2B-6, 16-oct-2026

Aplicación/extracción, validación y frascos: [candidato 13F, esquema y límites](../permisos-etapa2b6.md). Nuevas aplicaciones guardan autoridad explícita y las correcciones son anexas; administrar y extraer tienen permisos distintos. Incluye programación tipada y contrato de interfaz. Sin despliegue; alta, acciones completas de medicación, históricos, recetas/delegaciones/reportes/Storage/Edge siguen pendientes. No declarar terminado M6 ni abrir beta por este candidato.

## Avance 2B-7, 16-oct-2026

Alta revisada y seguimiento de dosis: [candidato 13G, esquema y límites](../permisos-etapa2b7.md). Posponer/no aplicada no administran ni extraen; el alta requiere habilitación y revisión de todos los pendientes. Se valida versión al aplicar y se conserva la primera resolución concurrente. SQL/UI preparados sin despliegue. El resto de rutas de recetas/delegaciones/reportes, lectura de bitácora/agregados, Storage/Edge, navegación e históricos sigue pendiente: no activar el corte ni declarar lista toda la beta.

## Revisión siguiente: recetas 13H, 16-oct-2026

Se revisó preparación → PDF → emisión y delegaciones: [hallazgos, esquema concreto, fases y decisiones](recetas-autorizacion-13h.md). La usuaria aprobó nombre y firma propia de quien realizó la consulta, datos del MVZ separados y controlados exclusivos del MVZ habilitado. Se preparó el [bloque parcial 13H1 de atestación y renderer](../permisos-etapa2b8-firma.md). **Las rutas de preparar/autorizar/emitir y Flutter todavía no lo consumen**; no declarar implementado el corte integral 13H. Conservar históricos y no desplegar ni abrir beta.

## Avance 2B-9, 16-oct-2026

El [candidato 13H2](../permisos-etapa2b9-recetas.md) conecta firma de consulta con preparación, autorización **individual**, PDF y emisión; incluye Flutter, corrección previa a emisión y guardas de artefactos. Sustituye la limitación de conexión descrita en 2B-8. No desplegado. Autorización permanente, dispensación, reportes, formatos y demás filas siguen pendientes: no declarar completo el corte de recetas ni abrir beta.

## Avance 2B-10 y 2B-11, 16-oct-2026

[13H3](../permisos-etapa2b10-a-cargo.md) añade autorización temporal de recetas ordinarias para casos seleccionados, aceptación y revisión posterior, sin compartir firma ni autorizar controlados. [13I1](../permisos-etapa2b11-dispensacion.md) sustituye la autoridad de dispensación física y cantidades; conserva cobro separado. Ambos son candidatos locales. Las referencias antiguas a autorización temporal pendiente describen el cierre previo a H3. La gestión completa de inventario/caja y lecturas aún requiere 13I2; no marcar terminada esa fila ni abrir beta.

## Avance 2B-12, 16-oct-2026

[13I2](../permisos-etapa2b12-inventario-caja.md) prepara permisos por persona para catálogo, entradas, ajustes, pedidos, fotos, frascos, cobros, cortes y referencias externas. Sustituye las dependencias por puesto de las rutas finales M8/M9 y referencias, protege lectura/exportación contable y conserva 13I1 para dispensación. SQL/Flutter locales, sin aplicar a Supabase ni abrir beta. Respaldos/agregados/identidad de otros módulos, reportes/formatos, Auth/Storage/Edge reales y el editor por lotes de producto siguen pendientes del cierre correspondiente.

## Avance 2B-13, 16-oct-2026

[13J1](../permisos-etapa2b13-reportes.md) prepara el corte del libro de controlados con permisos separados de preparación/emisión, MVZ habilitado y firma propia, registro/revisión del PDF y exportación con acceso actual. Rechaza formato oficial; no completa el Anexo 5 ni reportes generales. No aplicado a Supabase. Formatos/consentimientos y dependencias transversales siguen pendientes; no abrir beta.

## Avance 2B-14, 16-oct-2026

[13J2](../permisos-etapa2b14-plantillas.md) prepara consulta/edición/aprobación de plantillas y membrete por persona. La aprobación profesional no convierte fuentes en verificadas ni firma documentos. Flutter reconoce el alcance solo de plantillas y no consulta/emite documentos por esa capacidad. Preparación/firmas/autoridad/artefactos de documentos y demás dependencias siguen pendientes; no desplegar aisladamente ni abrir beta. Las recomendaciones y SQL nuevos están archivados para después de estas rondas, sin ejecución.

## Avance 2B-15, 16-oct-2026

[13J3](../permisos-etapa2b15-borradores-firma.md) añade borradores con MVZ elegido explícitamente y firma propia **de elaboración** para una revisión exacta. Esa firma no atribuye automáticamente atención clínica ni sustituye al tutor o autorización. Cierra mutaciones/firmas compartidas antiguas, conserva archivos ya firmados y conecta Flutter sin autoridad por puesto. Autorización, atribución clínica, aceptación del tutor, PDF/emisión y adaptación de otras pantallas siguen pendientes: no desplegar aisladamente ni abrir beta.

## Avance 2B-16, 16-oct-2026

[13J4](../permisos-etapa2b16-autorizacion-formatos.md) conecta atención/explicación firmada desde su propia cuenta, revisión individual del MVZ, tutor presencial, PDF exacto y permiso explícito de emisión. Sustituye las limitaciones de autorización/PDF de 13J3 en el contrato nuevo; no atribuye automáticamente procedimientos ni publica casos/observaciones desde formatos. Las pantallas clínicas antiguas y dependencias transversales aún requieren adaptación. Candidato local, sin despliegue ni apertura de beta.

## Avance 2B-17, 16-oct-2026

[13K](../permisos-etapa2b17-pantallas-clinicas.md) adapta las pantallas de casos existentes al contrato de acciones del servidor y a documentos firmados vinculados, sin depender del puesto ni publicar consultas/observaciones al emitir formatos. Incluye configuración explícita de ámbitos con los permisos existentes. No resuelve aún la creación de casos nuevos independientes del PDF ni constatación de muerte y rutas transversales pendientes. Sin despliegue ni apertura de beta.

## Avance 2B-18, 16-oct-2026

[13L](../permisos-etapa2b18-casos-independientes.md) permite registrar contexto de caso sin PDF con permiso explícito, paciente/MVZ elegidos y captura mínima. Conserva originales históricos y vincula hojas firmadas posteriores sin atribuir atención ni autorizaciones al registro inicial. Sustituye la limitación de creación de casos pendiente en 13K; constatación de muerte y dependencias transversales siguen pendientes. Sin aplicar a Supabase ni abrir beta.
