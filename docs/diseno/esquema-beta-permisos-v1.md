# Propuesta revisable: beta, permisos y recuperación — v1

Actualización: [v1.1](esquema-beta-permisos-v1.1.md) incorpora ajustes aprobados el 14 de octubre y prevalece en las diferencias. Se conserva v1 como antecedente.

Fecha: 14 de octubre de 2026. Estado: diseño para revisión; sin SQL ejecutado, sin cambios en Android y sin nuevas credenciales generadas. Decisiones de producto aprobadas por la usuaria; nombres, relaciones y mecanismos de esta propuesta sujetos a revisión. No incorporar referencias clínicas ni normativa como verificadas por aprobar este diseño.

## 1. Decisiones y secuencia

Producción: `io.github.alexcore123r.vetdosis`; beta: `io.github.alexcore123r.vetdosis.beta`, a partir del usuario GitHub actual Alexcore123R. Identificadores Android en minúsculas. El esquema de redirección OAuth debe revisarse por separado; no asumir que el callback actual cambia solo por cambiar applicationId.

A1: firma propia y estable, Android allowBackup=false y reglas de extracción compatibles con las versiones soportadas; versionCode incremental usando un contador CI estable por canal, sin reiniciarlo al modificar el workflow. Probar también la numeración de APKs separados por ABI. Llave y contraseñas solo en secretos del servicio; copia cifrada entregada por canal privado a la propietaria, nunca repositorio ni chat. Tener copia antes de depender de ella. Android no ofrece generar firma propia sin manejar material secreto: creación y entrega requieren ese canal.

Cambiar ID deja la beta instalada como aplicación distinta; cambiar firma con igual ID impide actualizar sobre la instalación anterior. No desinstalar ni transferir caché a ciegas. Verificar qué registros están en servidor y preparar exportación autorizada de lo que sea local. Causa del fallo anterior reportada y resuelta por la usuaria: almacenamiento insuficiente en su teléfono; no atribuirlo al ZIP ni a la firma.

A2: preparar candado en servidor y mantener admisiones desactivadas. A3: migrar permisos y probar dos cuentas/dos clínicas. Solo después abrir beta. Esto respeta el orden A1 → A2 → permisos, manteniendo permisos listos antes de admitir participantes.

## 2. Convenciones comunes

- UUID como identificadores; fechas timestamptz con hora de servidor; FK explícitas a auth.users, clinics y membresías.
- Referencias de clínica: claves compuestas (clinic_id,id) y FK compuestas donde una entidad depende de otra clínica. No confiar en clinic_id enviado por el cliente.
- RLS denegatoria por defecto. Tablas privadas de evidencia, invitaciones y secretos sin SELECT directo del cliente. Mutaciones solo RPC específicas, sin endpoint SQL genérico ni escritura libre con service_role.
- Concesiones y revocaciones anexadas, bitácora con actor, hora de servidor, referencia y motivo; no borrar historial para cambiar estado.
- Toda operación idempotente lleva operation_id y huella del contenido, con unicidad por actor/espacio/acción. Reusar el mismo ID con otro contenido se rechaza. Versiones optimistas y bloqueos transaccionales para saldo/cupos/consumo de invitaciones.
- Caducidad controla permisos actuales, sin alterar documentos históricos. Lectura/exportación siempre requiere membresía y permiso vigente, aunque el plan beta vencido permita modo lectura.

## 3. Acceso beta y versiones

### Nuevas entidades propuestas

| Entidad | Campos esenciales | Acceso |
|---|---|---|
| private.beta_email_approvals | id, email_normalized, approved_by, approved_at, revoked_at, reason | Administración de plataforma |
| private.beta_invites | id, token_hash UNIQUE, email_normalized, expires_at, consumed_by, consumed_at, revoked_at, created_by | Servicio; nunca devolver token_hash |
| public.beta_enrollments | id, user_id UNIQUE, starts_at, expires_at, source, approval_id/invite_id, accepted_terms_version, accepted_at | Usuario lee solo su estado seguro |
| private.beta_revocations | id, enrollment_id, reason, revoked_by, revoked_at | Plataforma; estado derivado seguro |
| public.beta_workspace_entitlements | id, clinic_id, enrollment_id, starts_at, expires_at | Consulta por membresía; no edición cliente |
| public.app_release_policy | channel PK, enabled, minimum_version_code, terms_version, policy_version, updated_at | Metadatos públicos sin secretos |
| public.app_releases | channel, version_code, package_id, released_at, expires_at, artifact_sha256, update_url | UNIQUE(channel,version_code); publicación por plataforma |
| public.terms_versions | version PK, text, content_hash, published_at | Contenido publicado legible |
| public.terms_acceptances | user_id, terms_version, accepted_at | UNIQUE(user_id,terms_version); confirmación autenticada |

Duración por persona: 60 días desde la primera admisión válida, no desde instalar ni descargar. Reinstalar/reintentar no reinicia plazo. Aviso al quedar siete días o menos; vencimiento exacto por reloj del servidor. Si llega a una clínica después, el beneficio vinculado termina con su inscripción; no otorga automáticamente 60 días nuevos a todos los miembros. La vigencia clínica efectiva depende de una concesión válida del espacio; quitar al patrocinador revoca la concesión vinculada. Esta regla de asignación es propuesta y requiere revisión explícita.

Invitación vinculada al correo verificado de Auth; consumo atómico, hash del token aleatorio y caducidad. No tokens en URLs de auditoría, analítica ni logs. Aprobación por correo y código son dos vías de entrada al mismo registro único, no dos plazos acumulables.

Reutilizar subscription_plans/subscription_grants y private.workspace_usage. Agregar plan beta no publicado para cobro; límites por tipo de espacio reutilizan los presupuestos actuales Individual/Clínica (2 GiB/10 GiB) como propuesta, no almacenamiento ilimitado. Estado Beta no confiere facultades clínicas. No reusar ni reiniciar las concesiones antiguas de migración como inscripción beta.

RPC propuestas: beta_status, beta_redeem_invite, beta_accept_terms; administración separada para aprobar/revocar correos, invitaciones y publicaciones. auth.uid y correo verificado se obtienen en servidor. Nunca permitir que admin de clínica otorgue acceso global beta.

Gate en cada RPC de mutación y en toda ruta equivalente, incluidos uploads Storage y Edge Functions. Impedir saltarse el candado mediante INSERT/UPDATE directo, endpoints antiguos o Storage. Tras vencer beta o build: solo lecturas/exportaciones autorizadas; exportar puede crear temporalmente un artefacto del propio usuario, con ruta específica, TTL y registro de auditoría. Aceptar términos, revocar sesión y otras acciones de seguridad siguen permitidas. Versiones antiguas bloquean nuevas escrituras y muestran actualización. Si un plan pagado vigente coexistiera con beta, debe definirse precedencia antes de activar cobros; por ahora no están activados.

No confiar en un version_code declarado por un cliente como prueba criptográfica del APK: controlar versión es compatibilidad, no attestation. El candado real de datos se basa en identidad, matrícula beta y permisos del servidor. La caducidad local del build también bloquea escrituras offline, pero reloj local/manipulación no constituye garantía. El servidor decide al sincronizar; operaciones rechazadas se conservan en cola sin presentarlas como confirmadas.

## 4. Puesto, habilitación y permisos

### Reutilizar y adaptar

Mantener clinics, clinic_members, professional_profiles y versiones privadas, case_staff_assignments, person_procedure_authorizations/revocations, professional_delegations/revocations y clinic_professional_authorizations. No recrear esas tablas ni duplicar el registro de aplicaciones/frascos.

Agregar a clinic_members `position_label` (texto visual) y `administrative_role` (owner/admin/member). El rol antiguo se conserva como legado durante transición, sin autoridad clínica en el modelo nuevo. El espacio personal mantiene un único miembro dueño. Ser administrador no habilita recetas, validación ni dispensación reservada.

| Nueva entidad/extensión | Campos esenciales | Reglas |
|---|---|---|
| private.professional_verifications | id, user_id, profile_version_id, license_number, reviewed_by, reviewed_at, evidence_path, evidence_hash, evidence_reference, valid_until opcional | Verificación de identidad/licencia; evidencia privada |
| private.professional_verification_revocations | verification_id, reason, actor, server_at | Anexada; mantiene evidencia histórica |
| public.clinic_responsible_appointments | id, clinic_id, professional_user_id, verification_id, proposed_by, proposed_at, accepted_at, valid_until | Titular acepta; habilitación vigente requerida |
| public.clinic_responsible_revocations | appointment_id, reason, actor, server_at | Revocable; impedir responsable activo inválido |
| public.operational_permission_grants | id, clinic_id, recipient_id, permission_code, procedure_type/document_type opcional, case_id opcional, granted_by, granted_at, valid_until | Persona y alcance explícitos; autoridad del otorgante comprobada |
| public.operational_permission_revocations | grant_id, reason, actor, server_at | Revocación efectiva inmediata |

Separar identidad/licencia verificada global de habilitación efectiva en clínica. Para actos reservados exigir ambas, membresía activa y permiso/relación responsable pertinente. No inventar vencimiento de una cédula: valid_until de la revisión puede ser opcional, con revocación; la designación y permisos sí tienen plazo explícito.

Primer MVZ: revisión fuera de la app por administradora de plataforma, registro privilegiado con evidencia y fecha. Usuario, admin clínico y MVZ no pueden aprobar su propia verificación. La identidad de administradora de plataforma viene de IAM/servicio y auditoría, no de un rol editable por la clínica. Revisores posteriores también deben actuar con identidad y alcance registrado; cualquier habilitación otorgada por responsable clínico queda limitada a su clínica, nunca crea una verificación global por sí sola.

Permisos iniciales técnicos: patient.read/write, appointment.read/manage, hospital.read/report/schedule, inventory.read/adjust, prescription.prepare/authorize, medication.report/validate, controlled.dispense, report.prepare/issue, form.prepare/authorize, backup.export/restore, workspace.manage. Catálogo de códigos versionado; tipos de procedimiento son identificadores de catálogo de la clínica, sin protocolos ni dosis implícitos. Faculdades reservadas requieren habilitación aunque alguien intente conceder el permiso.

Receta ordinaria: preparador registrado; responsable configurado y aceptación suya; autorización individual o permanente por tipo de documento, con vencimiento/revocación. Guardar preparador, autorizador, fechas servidor y concesión usada. Autorización permanente es acto previo explícito del MVZ, no atribuirle una revisión individual que no realizó. Reutilizar y restringir delegaciones actuales; dispensación de productos sujetos a receta y controlados solo MVZ habilitado. Firma del tutor siempre propia. Prohibir nuevas firmas profesionales compartidas por legado hasta revisar compatibilidad con este flujo; usar autorización y firma del titular según acto real, sin suplantar.

Impresión: título/cédula de firmante solo si hay habilitación vigente comprobada al emitir; rótulo neutro configurable en otros documentos, sin habilitar emisión de recetas reservadas. Snapshot histórico guarda identidad y autoridad utilizadas al emitir.

### Migración sin elevación automática

1. Inventariar RPC, RLS, Storage y funciones que hoy dependen de admin/mvz/auxiliar/recepcion/estilista.
2. Preparar entidades y controles nuevos con feature flag de plataforma y admisiones beta desactivadas.
3. Preservar membresías y datos. Copiar solo etiquetas visuales; mapear dueño/admin administrativo con inventario revisado. No generar verificaciones ni permisos clínicos a partir del rol anterior.
4. Revisar evidencia de habilitaciones previas; si no basta, dejar pendientes. Responsable y permisos nuevos se conceden explícitamente.
5. Cortar simultáneamente accesos antiguos de UI y servidor; no combinar el permiso nuevo con un OR de roles antiguos.
6. Mantener documentos ya emitidos, auditoría y originales; nuevas operaciones usan el modelo nuevo.
7. Probar permisos/aislamiento/revocación y activar admisiones. Rollback controlado mantiene clínica sin escrituras clínicas si hay fallo, no restaura privilegios inseguros.

## 5. Controlados y reportes

Reutilizar medication_product_versions y rx_regulatory_versions. Añadir catálogo de clasificación global versionado, con identidad de producto/principio activo y alcance de presentación explícitos, fuente, estado sin_verificar/verificada, vigencia y aprobador. No inferir clasificación por coincidencia de nombre. Guardar datos importados sin verificar; solo una revisión documentada habilita reglas normativas verificadas.

Propuesta: public.controlled_global_versions(id, product_identity_id/active_identity_id, scope, group_code, source, source_status, valid_from, valid_until, version, approved_by), y public.clinic_controlled_additions(id, clinic_id, product_identity_id, reason, source, state, created_by, created_at). El servicio administra el global; admin clínico agrega restricciones locales. No filas de exclusión o desclasificación clínica. Restricción efectiva es unión global + local; una adición local puede endurecer manejo interno sin afirmar una categoría legal verificada. Revocar una adición local nunca elimina clasificación global.

Registros pendientes, correcciones anexadas, frascos y movimientos existentes se mantienen. Solo MVZ habilitado valida/dispensa controlados/emite reportes reservados. Reportes de diseño conservan etiqueta visible `Basado en Anexo 5 — no oficial`, también en PDF/XLSX, hasta revisión del formato vigente. Una etiqueta no permite emitir como oficial. Folio oficial siempre capturado, no generado. Incluir pendientes e incidencias en aviso, no en conjunto validado del reporte. Retiro y conservación quedan sin mínimos numéricos inventados; reglas verificadas versionadas y snapshot en cada cálculo de fecha.

XLSX real con hojas/celdas tipadas, cantidad y unidad separadas, fecha y estado; no renombrar CSV. Campos de texto tratados como texto para evitar fórmulas de entrada. PDF y XLSX reproducen el mismo corte congelado y alcance del reporte.

## 6. Transferencias y respaldos

Reutilizar espacios personales y de clínica; no compartir el espacio personal con terceros. Nuevas tablas propuestas: public.transfer_jobs(id, owner_id, source_workspace_id, target_workspace_id, manifest_hash, state, created_at, committed_at, operation_id) y private.transfer_job_items(job_id, entity_type, source_id, source_version, selection, dependency_action, outcome_id). Manifiesto explícito firmado/hasheado; origen/destino y permisos comprobados otra vez al confirmar. Ver dependencias y conflictos antes de copiar. No transferir permisos, habilitación, membresías, claves, folios ni documentos emitidos como si su autoridad fuera portable. Datos de terceros requieren autorización y aviso; salir de clínica no copia expedientes al espacio personal.

Tres tipos separados: clínica; personal del dueño (preferencias, dosis/plantillas/firma propias, sin expedientes); cuenta individual (contenido de su espacio individual conforme al aviso de terceros). Contraseñas independientes; incluir firma propia solo cifrada y con consentimiento específico. Ficha de emergencia del personal permanece en servidor de clínica, excluida de esos respaldos. Cambiar de clínica no modifica el alcance del archivo personal.

Drive con drive.file y objetos accesibles por el usuario; tokens en almacén de secretos y no en exportaciones. Reutilizar cifrado y verificación de integridad existentes. Sin contraseña no hay recuperación del contenido cifrado; no prometer restablecerla.

Propuesta de restauración: private.restore_jobs(id, requested_by, backup_kind, artifact_path, artifact_hash, source_workspace_id, staging_workspace_id, manifest_version, state, created_at, expires_at), private.restore_preview_items(job_id, entity_type, source_id, action, validation_errors, conflict_reference), y clinics.workspace_state = active/restore_staging (no confundir con personal/clinic). Destino inicial nuevo y aislado, nunca sobrescribir clínica real. Staging no emite recetas, no activa alarmas/ventas ni concede autoridad. Vista previa de conteos, dependencias, identidades y conflictos; confirmación explícita para promover/copiar solo lo autorizado, con auditoría e idempotencia. TTL y cuota del staging se definen antes de implementar; evita almacenamiento ilimitado por restauraciones repetidas. Respaldo personal: restauración solo por su dueño autenticado. Clínica: admin o responsable habilitado con permiso; no todo MVZ.

## 7. Pruebas de aceptación antes de abrir beta

- ID/firma estables, versionCode ascendente por ABI y actualización instalada sin perder datos; confirmación del proyecto de pruebas embebido.
- Dos usuarios y dos clínicas reales: RPC, SELECT directo, Storage y Edge Functions; nunca datos cruzados.
- Invitación consumida una vez bajo concurrencia; correo distinto rechazado; revocación; reinstalación no reinicia 60 días.
- Aviso siete días; vencimiento/build mínimo bloquean mutación por todas las rutas y permiten lectura/exportación autorizada.
- Admin sin habilitación no emite; etiqueta de puesto no concede permisos; revocación entre preparar y emitir se rechaza; firma del tutor no delegada.
- Control global no se quita localmente; adición no inventa categoría normativa; validación no duplica descuento de frasco.
- XLSX abre como XLSX, con tipos correctos; reporte conserva etiqueta no oficial y corte.
- Restauración errónea/contraseña incorrecta queda aislada; vista previa no muta producción; dueño personal comprobado; conflictos y reintentos no duplican datos.

## 8. Puntos para aprobación del esquema

1. Tablas beta y regla de activación/beneficio por usuario y espacio, 2 GiB/10 GiB y tratamiento de concesiones antiguas.
2. Separación administrativo/puesto/verificación global/habilitación clínica, matriz de permisos y tratamiento de delegaciones/firmas antiguas.
3. Unión de catálogo global + restricciones locales y distinción entre categoría normativa verificada y restricción interna.
4. Restauración aislada, promoción explícita, alcance de respaldos, cuotas/TTL y retención de evidencia privada (sin plazo normativo inventado).
5. Caducidad de build independiente de los 60 días por persona: duración exacta por publicación todavía pendiente. Contador de versión y canal de entrega de llave/firma deben confirmarse antes de configurar A1.

Tras revisión, producir migraciones pequeñas numeradas después de las ya aplicadas, esquema de rollback, matriz RLS/RPC y pruebas. No ejecutar de nuevo los scripts históricos 01–08 ni conceder privilegios por la aprobación documental.
