# Paquete de aplicación: Carnet preventivo y Agenda

Estado: instrucciones para una actualización aditiva del proyecto de pruebas.
Este documento no aplica cambios al servidor. Confirmar el proyecto y su estado
actual el día de la aplicación; no reutilizar como evidencia actual los reportes
remotos fechados anteriormente.

## Qué incluye

- `supabase/adaptations/preventive_booklet_v2.sql`: contrato SQL v2 del Carnet
  preventivo (evidencias, planes, retiros y enlace a citas), aditivo y transaccional.
- `supabase/adaptations/appointment_patient_search_v2.sql`: amplía los tipos de
  cita y la búsqueda de paciente por nombre, especie, tutor, teléfono y, con
  permiso clínico, notas.
- `supabase/proposed/13O_permission_backups_exports.sql`: el exportador detecta
  las cuatro tablas del Carnet al momento de exportar, si existen.

La migración inicial de permisos de 23 candidatos ya figura como instalada en
el proyecto de pruebas en el registro histórico. **No volver a ejecutarla.** La
actualización aquí descrita no instala ni reactiva beta, no crea concesiones,
no carga datos clínicos ficticios y no publica funciones Edge ni APK.

## Requisitos antes de aplicar

1. Confirmar que se está en el proyecto de pruebas esperado y que la beta sigue
   cerrada. Recargar el catálogo remoto actual; los resultados anteriores no
   prueban que el esquema no haya cambiado desde entonces.
2. Generar y descargar un respaldo cifrado reciente de base de datos, comprobar
   SHA-256 y lectura con `pg_restore --list`, y conservar una copia privada fuera
   de la retención de Actions. Revisar por separado Storage. El ensayo aislado
   histórico no equivale a un respaldo actual ni a una recuperación completa.
3. Revisar que M4/M9, permisos 13B/13C, políticas beta/permisos y los objetos
   esperados estén presentes y sin deriva. No reejecutar `CREATE TABLE` para
   reparar un esquema parcial.
4. Conservar las pruebas locales aprobadas y revisión de cambios como evidencia.
   No hacer la aplicación si cualquier precondición falla o si hay dudas del
   destino, respaldo o estado de las políticas.

## Orden de aplicación

1. Aplicar `supabase/proposed/13O_permission_backups_exports.sql` solo si el
   catálogo fresco muestra que 13O aún falta y después de revisar su hash y
   dependencias. Si ya está instalada, no volver a correrla: este candidato no
   es una migración de actualización repetible.
2. Aplicar `supabase/adaptations/preventive_booklet_v2.sql` en una transacción.
   Requiere las tablas/funciones clínicas y de agenda que usa el archivo. Si
   encuentra objetos v2 existentes o la guarda de beta/permisos falla, detenerse
   y comparar definiciones; no forzar ni borrar objetos.
3. Aplicar `supabase/adaptations/appointment_patient_search_v2.sql` en su propia
   transacción, después del contrato de permisos. Verificar la restricción de
   tipos de cita y la definición de `ops_patient_search`.
4. Recargar el esquema de PostgREST (la adaptación de Agenda ya envía la
   notificación) y desplegar el cliente compatible solo después de confirmar el
   contrato remoto.

No ejecutar el generador del corte inicial con `--commit` como parte de esta
actualización. `scripts/supabase/integration_bundle.py` compone el paquete base
de 23 candidatos y sus guardas lo rechazan si ya está instalado.

## Verificaciones locales

Desde la raíz del repositorio:

```bash
bash supabase/tests/run_integration_bundle.sh
bash supabase/tests/run_permission_backups_exports.sh
git diff --check
```

La segunda prueba integra el orden 13O → Carnet v2 → búsqueda/Agenda y comprueba
exportación de sus cuatro tablas, búsqueda por teléfono, protección de notas por
permiso y tipos de cita. Estas pruebas usan PostgreSQL local con datos sintéticos;
no sustituyen verificaciones HTTP contra el Supabase remoto.

## Verificación posterior en el entorno de pruebas

- Volver a consultar el catálogo y confirmar las funciones, tablas, triggers,
  restricción de `kind`, grants y políticas resultantes.
- Con dos cuentas y clínicas separadas, probar Carnet, evidencia, permisos,
  búsqueda por teléfono, búsqueda de notas con/sin `clinical.read`, y creación de
  citas de consulta, vacunación, cirugía, análisis y visita hospitalaria.
- Revisar exportación de respaldo y confirmar que incluye filas de las cuatro
  tablas del Carnet cuando estas contienen datos.
- Comprobar errores, RLS y aislamiento por clínica; conservar reporte, commit,
  hashes y hora de aplicación. Mantener admisiones cerradas hasta completar la
  aceptación de cliente/Edge por separado.

## Limitaciones abiertas

- Los datos del Carnet se incluyen en exportación, pero el flujo de restauración
  todavía no importa estas cuatro tablas. El Carnet no tiene restauración de
  extremo a extremo.
- La prueba de Agenda verifica el contrato SQL, no notificaciones, interfaz,
  alarmas ni todas las operaciones reales de la app.
- El orden aquí es condicional a un inventario actual: si 13O ya está presente,
  se omite; si cualquiera de las adaptaciones v2 ya existe, se inspecciona y se
  prepara una actualización aditiva en vez de repetirla.
