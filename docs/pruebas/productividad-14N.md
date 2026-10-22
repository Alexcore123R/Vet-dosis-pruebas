# Plan semanal a tareas revisadas

Aplicar `supabase/proposed/14N_week_plan_tasks.sql` después de 14L y 14M. No sustituye esas migraciones. La app usa el permiso vigente `team.manage` y el plan de clínica que ya requiere Productividad.

1. Abrir Productividad y semana → Crear tareas desde el plan.
2. Revisar el texto del plan. Agregar tareas manualmente o pedir una propuesta a IA con el proveedor configurado.
3. Revisar fechas, duración, responsable, área, instrucciones y prioridad. Se permite dejarlas sin asignar. Seleccionar las tareas que se desean crear.
4. Resolver avisos de disponibilidad, carga diaria y duplicados; marcar la revisión y guardar.
5. Comprobar que aparecen en la semana y que el plan conserva el texto revisado. Un colaborador conserva la vista de tareas permitida por sus permisos.

La IA recibe identificadores anónimos del equipo y carga operativa; no recibe nombres del directorio automáticamente. El texto del plan se envía tal como lo revisa el encargado. La propuesta es local hasta confirmar el guardado.

El servidor guarda plan, lote, tareas y auditoría en una sola transacción. Recomprueba responsables, disponibilidad y carga diaria; rechaza cambios concurrentes del texto del plan. Un reintento conserva el identificador de operación; el mismo lote normalizado también se reconoce con una operación nueva. Si se pretende repetir deliberadamente una tarea, debe distinguirse por título, fecha, responsable o área.

Validación automatizada:

- `test/weekly_task_draft_test.dart`: límites, fechas y responsables de la respuesta, disponibilidad, carga y duplicados.
- `test/weekly_plan_tasks_test.dart`: edición local, revisión obligatoria y reintento con el mismo identificador.
- `supabase/tests/week_plan_tasks.sql`: transacción completa, reintentos, permisos, disponibilidad, capacidad y rechazo de plan desactualizado.

Prueba de PostgreSQL:

```sh
bash supabase/tests/run_permission_clinic_operations.sh \
  supabase/proposed/14L_clinic_productivity.sql \
  supabase/tests/clinic_productivity.sql \
  supabase/proposed/14N_week_plan_tasks.sql \
  supabase/tests/week_plan_tasks.sql
```
