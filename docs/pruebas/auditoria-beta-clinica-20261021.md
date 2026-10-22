# Auditoría de preparación — beta clínica para revisión de Johana

**Fecha de corte:** 21-oct-2026. **Código examinado:** rama `feature/historia-carnet-20261020` (`d940f435`).
**Objetivo:** entregar una aplicación instalada y capaz de completar una atención clínica **con datos ficticios** de manera que Johana y su clínica encuentren errores funcionales antes de revisar e incorporar referencias bibliográficas. El resultado de una prueba sintética o una compilación **no habilita uso clínico real**.

## Clasificación

- **Existe en código**: interfaz, RPC/adaptación o prueba identificada en la rama; NO implica que exista en Supabase remoto.
- **Validación automatizada**: resultados de GitHub Actions / fixtures sintéticos, no equivalentes a un caso completo probado en un teléfono conectado a servidor.
- **Pendiente en equipo**: instalación, sesión real, permisos, versiones de la BD y recorrido de atención aún por comprobar.
- **Fuera del primer corte**: pendiente explícito que no se debe simular ni anunciar como terminado.

## Evidencia recuperada

- [Rama de trabajo y PR #7](https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/7): 61 commits por delante de `main`, con cambios en 213 archivos. PR borrador y pila de PR #2→#3→#4→#7 aún no fusionada.
- [GitHub Actions de historia/carnet, run 39699054513](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39699054513): 463 pruebas Flutter, análisis, SQL seleccionado y compilación Android debug aprobados.
- [APK firmado de la misma rama, run 39699046850](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39699046850): build release y firma verificados en CI. **Actualización de la usuaria:** la compilación antigua no se instalaba, pero las actualizaciones nuevas **sí se instalan**. Falta anotar la versión efectivamente instalada y verificar funcionamiento real.
- Los scripts de esta PR ejecutan **ocho suites PostgreSQL 17 sin red**, cada una con sus fixtures y concurrencia donde aplica. Se añade regresión Flutter de 13 archivos. Esto amplía la cobertura agrupada, pero no prueba el encadenamiento end-to-end entre seis módulos.

## Matriz de revisión

| Tramo | Código/preparación identificado | Bloqueo para prueba de Johana | Prueba manual mínima |
|---|---|---|---|
| **Acceso** | Auth, clínicas, permisos explícitos, selección de clínica | Confirmar sesión/habilitación real de la revisora y dos clínicas distintas; no convertir rol admin en facultad MVZ | Entrar como MVZ autorizado y como recepción sin autoridad clínica; revocar durante captura |
| **Pacientes / tutor** | Alta, historial estructurado, contacto principal/secundario, bitácora; carnet v2 como adaptación | Contratos remotos (M4, paciente, tutor, booklet, patient_contacts) y restauración de nuevos registros | Crear tutor + paciente; abrir, corregir con nueva entrada, salir/volver a entrar, comparar expediente |
| **Agenda** | Cita, vinculación a paciente, atención del día, ingreso→listo→entrega | `appointment_care_v1.sql`, `appointment_patient_search_v2.sql`, concesiones; recorrido sin cita no completado | Crear cita, mover, reprogramar/cancelar otro caso, registrar ingreso, autorizar recogida, cerrar consulta y entregar |
| **Consulta** | Historia, SOAP, constantes, casos independientes, guardas de autoridad | Confirmar migraciones clínicas/13K/13L y documentos con perfil autorizado en proyecto real | Registrar anamnesis/mediciones/nota; confirmar autor y fecha; abrir de nuevo; verificar que recepción no ve notas |
| **Receta y PDF** | Preparación, firma propia de consulta, autorización individual, revisión del PDF y emisión separados (13H2/13H3) | Migraciones 13H1–H3, RPC/Edge/Storage en remoto, firma y estado real; cierre de Agenda **no** crea receta automáticamente | Preparar receta desde caso, autorizar con responsable, generar/abrir PDF; revocar antes de emitir y comprobar rechazo |
| **Caja / cobros** | POS, actos de servicio y cobro, lectura de saldo y ventas anuladas; solicitud de CFDI (no timbrado) | 13I2 y funciones 14D–14G pendientes de verificación remota; importe parcial **no es abono real** | Registrar servicio, cobrar una vez, comprobar total y ticket; repetir envío, reversar, revisar inventario y saldo de cita |
| **Hospitalización** | Alta flexible, hoja de evolución, administración registrada, resolución/alta con permisos tipados | Migraciones 13D–13G, datos de admisión, vinculación/cierre; validar realmente en servidor | Crear estancia sin jaula asignada, anexar observaciones, registrar medicación solo con permiso y alta sin duplicar administración |
| **Formatos / notas** | Documentos borrador, firma/atención/tutor, edición y PDF 13J4; borradores asistidos 14M | Confirmar Edge/Storage/contratos nuevos; IA solo redacta borrador revisable | Guardar borrador, salir, recuperarlo, firmar con identidades distintas, generar y reabrir PDF |
| **Biblioteca** | PR #10 staging de fuentes (independiente) | No importadas referencias; sin interfaz de revisora; no activar calculadora clínica | Solo después de estabilidad: exponer consulta de registros pendientes a Johana |

## Recorrido E2E obligatorio (ficticio, un único paciente)

Usar identificadores de prueba sin coincidencia con personas/animales reales, por ejemplo clínica `Prueba-Johana`, tutor `TUTOR FICTICIO A`, paciente `PACIENTE FICTICIO A`. Guardar número de compilación y hora, usuario/rol, zona horaria de clínica y versión de los contratos (no contraseñas ni tokens).

1. **Paciente y tutor:** alta con datos ficticios; volver a consultar desde otra pantalla y verificar que no se pierde información.
2. **Agenda:** registrar cita de consulta y vincular exactamente al paciente creado; comprobar día/hora en la zona de la clínica.
3. **Ingreso:** registrar pertenencias, servicios y autorización, sin crear automáticamente una venta ni un consentimiento.
4. **Consulta:** añadir anamnesis y nota, una observación estructurada y, si procede, la evolución; comprobar autor real y que la nota no aparece a recepción.
5. **Receta:** preparar con permiso, autorizar con sesión del responsable MVZ habilitado, firmar y abrir PDF con los datos ficticios. **La receta es un flujo distinto de cerrar Agenda.**
6. **Caja:** crear/cobrar el servicio, verificar importe exacto, estado financiero de cita y comprobante; repetir misma operación para detectar doble cargo. Probar anulación con permisos.
7. **Agenda/entrega:** marcar listo/entregado; comprobar que entregar no marca pagado y que pagar no cierra clínicamente la consulta.
8. **Persistencia:** cerrar sesión/app, volver a entrar, revisar paciente, cita, nota, receta, venta y bitácora. Confirmar que clínicas/cuentas ajenas no acceden.

## Negativos que deben bloquear aprobación

- Revocar permiso a mitad de edición y comprobar rechazo en servidor y limpieza de datos privados.
- Intentar abrir una receta/expediente de otra clínica con cuenta diferente.
- Guardar dos veces al perder respuesta de red: no debe duplicar ni consulta ni cobro.
- Emisión de receta con responsable no habilitado, documento sin firmar o versión caducada: rechazar.
- Baja/alta de hospitalización no debe registrar medicación como administrada implícitamente.
- Cita cancelada o reversión financiera no debe contarse como venta activa.
- Fallo de paquete Android, fallo de pantalla a 320 px/texto ampliado, permisos de almacenamiento/compartir y retorno al reabrir la app.

## Bloqueos ya documentados (sin ocultarlos)

**P0 — instalación corregida, compatibilidad remota pendiente:** la usuaria confirmó que las actualizaciones nuevas sí se instalan; no confundir el error de una versión anterior con un bloqueo persistente. Anotar build en Ajustes y validar apertura, actualización y persistencia en su teléfono. Sigue sin haber un ensayo autenticado de cadena completa en Supabase. Antes de desplegar SQL: revisar inventario, respaldo verificable, dependencias y permisos; mantener beta cerrada.

**Inspección remota de solo lectura del 21 de octubre (run 39710969017):** todas las dependencias básicas comprobadas aparecen presentes (`missing: []`), incluidas tablas de pacientes, citas, recetas, hospitalización, formularios, inventario y términos. Sin embargo, `private.beta_policy` registra `admissions_enabled=false` y `enforcement_enabled=false`; `private.permission_policy` registra `enforcement_enabled=false`, `migration_reviewed=false`. La función `app_module_workspace` difiere de la definición candidata, por lo que **no se debe sobrescribir ni asumir compatibilidad sin comparar el origen**. `restore_stage` figura ausente en la inspección de presencia seleccionada. La herramienta indicó `deploy_ready=false`, no un permiso para desplegar. La inspección de presencia y hashes no acredita por sí sola reglas RLS efectivas, sesiones Auth, Edge, firma real o conservación de datos.

**P1 — brechas funcionales:** abonos/anticipos en **un solo acto** aún no implementados, cierre clínico de cita no emite receta, recorrido equivalente **sin cita** aún pendiente, adjuntos/carnet y restauración completa de tablas nuevas no terminados. No presentar saldo 'abonado' de varios servicios como abono parcial de una factura.

**P1 — integración:** la rama contiene migraciones `14G–14M` propuestas, no acreditadas como aplicadas; promoción/IA/inventario pueden mostrar error de RPC. No prometer acceso a IA, generación documental real, ni envío externo automático.

**P2 — ampliaciones posteriores:** catálogo bibliográfico, fluidoterapia, referencia de laboratorio, recomendaciones de dosis y automatizaciones no verificadas. Mantenerlos fuera del motor de decisiones clínicas hasta revisión veterinaria por Johana/colaboradores.

## Puerta de salida para entregar a Johana

- [x] La usuaria informa que las versiones nuevas sí se instalan (falta documentar el build).
- [ ] Se comprueba la actualización, inicio de sesión, persistencia y apertura de módulos en el dispositivo real.
- [ ] Se acredita Supabase de **pruebas** con respaldo reciente, definiciones compatibles, permisos efectivos y Auth en dos cuentas/clínicas; la inspección remota P0 detectó un corte de permisos todavía desactivado.
- [ ] CI de esta auditoría aprueba suites SQL de Pacientes, Agenda, Consulta, Recetas/PDF, Formatos/PDF, Hospital y Caja; y regresiones Flutter.
- [ ] Se completan los 8 pasos del recorrido E2E con datos ficticios y resultado/evidencia por paso.
- [ ] El personal no autorizado no puede ver datos privados, emitir recetas, registrar medicación o cobros.
- [ ] Fallos/reintentos y reinicio de app no alteran saldos ni duplican registros.
- [ ] La lista de limitaciones se entrega a Johana; ninguna función incompleta se etiqueta como lista.

### Alcance y límites de la auditoría

Esta PR **no** modifica datos, usuarios, permisos, Edge Functions, despliegues ni APK. Las suites son independientes: **no verifican** una operación real que atraviese los seis módulos en la misma base o sesión. El checklist manual es necesario incluso si todas las pruebas salen verdes. Las credenciales de un entorno clínico jamás deben adjuntarse al informe.

## Registro legal y siguiente auditoría
La [PR #12](https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/12) propone la presentación **previa al registro** de los términos/privacidad publicados, con dos casillas y revisión de versión. No confundir esta confirmación con el recibo servidor, que actualmente se genera al inscribirse a la beta. Los textos aún son borradores y la función 12D no está aplicada.

Tras cerrar P0 y el recorrido funcional, revisar **Recetas** y **Equipo** según el listado de pendientes que comunique la usuaria, antes de habilitar la beta a la clínica colaboradora. No inventar requisitos no especificados.
