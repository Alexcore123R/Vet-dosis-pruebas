# Permisos etapa 2B.21: respaldos y exportaciones

Estado: candidato local, sin aplicar a Supabase remoto.

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
