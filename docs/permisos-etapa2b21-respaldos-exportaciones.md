# Permisos etapa 2B.21: respaldos y exportaciones

Estado: candidato local, sin aplicar a Supabase remoto.

## Corrección de revisión del 17 de octubre de 2026

Los apartados históricos que dicen que no existe importación quedaron superados
por 13U/13V: sí existen funciones que crean tutores y pacientes. Ahora ambas
exigen un destino de prueba registrado en `private.backup_restore_test_targets`,
con vencimiento máximo de 14 días. La lista se crea vacía y las cuentas de la app
no pueden modificarla. Permisos de restauración y administración siguen siendo
obligatorios. La interfaz oculta las acciones de aplicación sin esa habilitación.
Ninguna clínica operativa se habilita automáticamente.

Esta restricción bloquea la restauración directa en clínicas ordinarias. El flujo
completo de recuperación a un espacio de prueba independiente y posterior
transferencia elegida sigue pendiente; no se considera terminado por tener una
tabla de staging. Las pruebas registran exclusivamente su clínica sintética.

Las verificaciones de formato, clínica, archivo, manifiestos, preflight y payload
usan comparaciones que rechazan valores NULL. Las estadísticas financieras
devuelven `species: null` sin `appointment.read` y `low_stock: null` sin
`inventory.read`, evitando que `sales.read` amplíe esos accesos.

## Alcances

- **Clínica:** exige membresía vigente, `backup.export` y además `workspace.manage` o ser el MVZ responsable vigente. La etiqueta visual `admin` no concede acceso.
- **Personal:** solo el dueño del espacio personal. Incluye dosis propias, plantillas creadas por esa persona y su perfil profesional versionado. Excluye pacientes, tutores, expedientes, hospitalización, documentos y firmas capturadas en documentos.
- **Estadísticas:** exige `sales.read`; no se deriva de `backup.export`.
- La beta vencida conserva lectura y exportación mediante `beta_access_check(false, ...)`.

Los dos archivos conservan hash, cifrado local y contraseña elegida por la persona. La interfaz recuerda usar contraseñas separadas. No se guardan contraseñas en servidor ni en el repositorio.

## Recuperación

`Revisar respaldo para recuperación` descifra e inspecciona el archivo localmente. Valida formato, hashes, clínica, identificadores duplicados y mezcla de clínicas. No escribe en producción y no acredita que el archivo sea restaurable por completo.

La restauración permanece pendiente para la fase aprobada: un espacio staging por espacio, TTL de 14 días y vista previa antes de cualquier transferencia. Esta migración no añade una ruta de restauración.

## Aplicación coordinada

`13O_permission_backups_exports.sql` reemplaza el contrato `app_module_workspace` y las funciones de exportación/estadísticas. Debe publicarse junto con el cliente que entiende los módulos `backup` y `statistics`; no admite despliegue parcial. La migración conserva la cadena histórica que agrega pagos, conversaciones propias y agenda al respaldo operacional.

## Evidencia local

```bash
bash supabase/tests/run_permission_backups_exports.sh
bash supabase/tests/run_module_navigation_dashboard.sh
flutter analyze
flutter test
```

Las pruebas usan cuentas y contenido sintéticos. Cubren anonimato, usuario ajeno, rol visual sin capacidad, autoridad incompleta, separación de estadísticas, propiedad personal, allowlist personal y revocación inmediata.

Validación del candidato `4d7e8b3`: 351 pruebas Flutter y 22/22 trabajos del corte de permisos aprobados en [GitHub Actions](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38985700276).


## Vista previa de restauración (13Q)

Se añadió un candidato posterior, `13Q_restore_preview_staging.sql`, que **no restaura datos todavía**. Su única función es preparar de forma segura una restauración futura:

- exige `backup.restore` y además `workspace.manage` o responsabilidad profesional vigente;
- el rol visual `admin` por sí solo no concede acceso;
- admite únicamente respaldos operacionales v1 de la misma clínica;
- registra hash SHA-256, fecha del respaldo y conteos por tabla, pero no almacena ni importa las filas del respaldo;
- existe un solo staging por clínica; preparar otro reemplaza el anterior con un `stage_id` nuevo;
- caduca a los 14 días y puede descartarse explícitamente;
- devuelve siempre `imports_applied: false` y las pruebas comprueban que el número de pacientes no cambia durante la vista previa.

La pantalla de respaldo puede enviar esta previsualización al servidor solo después de que el archivo haya sido descifrado y verificado localmente. El hash enviado corresponde al archivo de respaldo ya verificado, de modo que una fase de aplicación futura deberá exigir exactamente el mismo contenido antes de considerar una importación.

La restauración efectiva, resolución de conflictos, inserción de filas y recuperación de adjuntos siguen fuera de este candidato.


## Previsualización de conflictos (13R)

El candidato `13R_restore_conflict_preview.sql` continúa sin restaurar filas. Usa el respaldo ya verificado y el staging activo para comparar solamente identificadores UUID de un conjunto acotado de tablas operacionales principales.

La app deriva localmente un manifiesto determinista de identificadores a partir del archivo verificado, calcula su SHA-256 y lo envía junto con el hash del respaldo y el `stage_id`. El servidor rechaza el análisis si cualquiera de esos vínculos no coincide con el staging vigente.

El reporte separa por tabla:

- identificadores entrantes;
- identificadores que ya existen en la misma clínica;
- identificadores nuevos;
- una muestra acotada de hasta 100 IDs en conflicto, con indicador cuando hay más.

El manifiesto acepta como máximo 25 000 identificadores y solo tablas en una allowlist explícita. No permite consultar nombres de tabla arbitrarios. La comparación está limitada a la clínica del staging y no modifica tablas operacionales.

Por ahora la allowlist cubre: tutores, pacientes, casos clínicos, hospitalizaciones, documentos, recetas, frascos, inventario/lotes, citas, tareas y mensajes. Las demás tablas permanecen pendientes para una fase posterior de dependencias y orden de importación.

La interfaz muestra conteos de «sin choque» y «ya existentes», pero todavía no ofrece políticas de reemplazo, mezcla ni inserción. `imports_applied` permanece en `false`.


## Simulación de decisiones (13S)

El candidato `13S_restore_decision_preview.sql` toma el staging y la comparación de conflictos y produce un plan **sin escribir datos operacionales**. El archivo verificado genera además un manifiesto determinista de dependencias por registro; su hash queda ligado al staging para detectar cambios entre la revisión y cualquier fase posterior.

La política actual es deliberadamente conservadora:

- un ID que ya existe en la misma clínica se clasifica como `keep_existing`; nunca se sobrescribe;
- un ID nuevo con dependencias satisfechas queda como `create_candidate`;
- una dependencia de entidad que no existe queda `blocked_missing_dependency`;
- una referencia a personal que ya no pertenece a la clínica queda `manual_review`;
- un mismo ID que existe en otra clínica o en un ámbito distinto queda `blocked_foreign_identity`;
- no existen todavía políticas de mezcla ni reemplazo: `overwrite=false` y `merge=false`.

La simulación propaga dependencias principales: tutor → paciente; paciente/plantilla/personal → documento; paciente/documento/personal → caso clínico; caso/perfil/delegación → receta; inventario → lote/frascos; y las referencias de agenda/tareas/mensajes al personal vigente. Las versiones de plantilla que dependen de otra versión entrante sin orden resuelto quedan en revisión manual, no se adivina un orden.

La comparación de IDs también distingue colisiones de otra clínica. Una identidad UUID existente fuera del espacio destino no se considera «nueva»: queda bloqueada antes de cualquier decisión de importación.

El reporte mostrado en la app resume por tabla: candidatos a crear, registros actuales que se conservarían, bloqueos por dependencia, colisiones de otro espacio y revisiones manuales. Sigue devolviendo `imports_applied=false`.


## Preflight de aplicación (13T)

El candidato `13T_restore_application_preflight.sql` es el último seguro previo a una futura restauración. **No existe todavía una función de importación** y este preflight no inserta, actualiza, mezcla ni elimina filas operacionales.

El preflight exige el mismo `stage_id` y los mismos hashes de archivo, manifiesto de conflictos y manifiesto de dependencias que fueron usados para construir el plan. Si cualquiera cambia, la revisión se rechaza.

Además vuelve a consultar el estado actual del servidor para detectar deriva ocurrida después de la simulación:

- un `create_candidate` que ahora ya existe queda bloqueado;
- un UUID que apareció en otra clínica queda bloqueado;
- un `keep_existing` que desapareció queda bloqueado;
- referencias a personal, catálogos o entidades padre se vuelven a comprobar;
- una dependencia entrante solo es válida si su decisión sigue siendo `create_candidate` o `keep_existing`;
- estados de plan desconocidos fallan cerrados.

El resultado es únicamente `applicable=true/false`, una lista de bloqueos y un identificador de preflight. Cuando es aplicable, la ventana informativa es de 15 minutos; una futura operación real deberá volver a validar el estado y no puede tratar esta ventana como autorización permanente.

Cualquier `blocked_missing_dependency`, `blocked_foreign_identity`, `manual_review`, política de overwrite/merge o deriva detectada produce `applicable=false`. El reporte conserva `imports_applied=false`.


## Primera restauración real: tutores solamente (13U)

El candidato `13U_restore_owners_apply.sql` habilita la primera escritura real de recuperación, limitada exclusivamente a `vet_owners`.

La app extrae las filas de tutores únicamente después de verificar el archivo localmente. El servidor prepara ese payload contra el `stage_id`, el hash del respaldo, el manifiesto de IDs y el plan de decisiones. Preparar el payload invalida cualquier preflight anterior, por lo que el preflight debe ejecutarse después de la preparación.

La aplicación exige un preflight vigente y aplicable. Dentro de la misma transacción vuelve a comprobar **todos** los tutores antes de insertar el primero:

- `keep_existing` debe seguir existiendo y nunca se modifica;
- `create_candidate` debe seguir sin existir en ninguna clínica;
- cualquier deriva cancela la función completa;
- no hay `UPDATE`, `UPSERT` ni merge;
- la operación es idempotente para el mismo payload después de un éxito.

Los tutores nuevos conservan nombre, teléfono, correo, dirección y fecha histórica de creación cuando es válida. `created_by` se atribuye al usuario que ejecuta la restauración para no falsificar una autoría activa; el autor original, cuando existe en el respaldo, se conserva solo en la auditoría como `source_created_by`.

Cada fila creada genera `owner_restored_from_backup` y la operación completa genera `backup_restore_owners_applied`. El reporte usa `imports_applied=true` por primera vez, pero con `scope=vet_owners`, `overwrite=false` y `merge=false`.

Pacientes, expedientes, hospitalización, recetas, inventario, documentos y cualquier otra tabla siguen sin una ruta de aplicación real.

## Revisión de integración Carnet/Agenda — 20 de octubre de 2026

El exportador de clínica añade `preventive_evidence`, `preventive_plans`,
`preventive_plan_retirements` y `preventive_appointment_links` si esas tablas ya
existen al momento de exportar. El control se hace al ejecutar el snapshot, por
lo que el corte 13O puede instalarse antes de la adaptación de Carnet v2.

`appointment_patient_search_v2.sql` queda como adaptación transaccional posterior
al corte de permisos. Requiere la función de agenda de 13B, `clinical.read` de
13C, y las tablas clínicas/operativas de M4/M9. El acceso a tutor/teléfono requiere
`patient.read`; la búsqueda de notas clínicas requiere además `clinical.read`.

La regresión integrada ejecuta, en orden, 13O, Carnet v2 y la ampliación de
búsqueda; verifica la exportación de filas sintéticas de las cuatro tablas,
búsqueda por teléfono, ocultamiento de notas sin permiso y acceso a notas con
`clinical.read`, además de los tipos ampliados de cita. Ejecución local:
`bash supabase/tests/run_permission_backups_exports.sh`.

**Límite pendiente:** el respaldo conserva esas tablas, pero la inspección de
recuperación no las importa. Los candidatos de restauración siguen limitados a
los alcances descritos arriba; Carnet v2 no se considera restaurable todavía.
