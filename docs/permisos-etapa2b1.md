# Permisos 2B-1: registro administrativo de pacientes y tutores

Estado: candidato implementado y probado en PostgreSQL local aislado. No aplicado al proyecto Supabase de pruebas. No cambia el APK, no verifica profesionales y no abre beta. Continúa el esquema beta-permisos aprobado, sin crear códigos nuevos ni conceder permisos automáticamente.

## Cambio concreto

| Ruta | Comportamiento del candidato |
| --- | --- |
| `create_vet_patient` | Requiere concesión vigente `patient.write` de la persona y membresía actual de esa clínica; ni admin ni MVZ tienen excepción por rol |
| SELECT `vet_patients` | RLS exige `patient.read` de la persona para esa clínica |
| SELECT `vet_owners` | RLS exige el mismo permiso de lectura; escribir no habilita lectura de contactos |
| Auditoría `patient_created` | Conserva autor y hora de servidor; añade ID de la concesión que autorizó la operación |

El RPC conserva la validación de entradas y el mecanismo previo de idempotencia por persona, clínica y operación. La autorización ocurre antes de recuperar una respuesta de reintento: una operación guardada no permite saltarse una revocación posterior. No cambia expedientes ni textos clínicos existentes.

El alta bloquea la fila de clínica como la administración de concesiones, y conserva un bloqueo compartido de la membresía durante la escritura. Una revocación que toma primero ese bloqueo se confirma antes de evaluar el permiso. También se comprueba la vigencia con el reloj actual después de esperar, evitando utilizar una concesión que venció mientras la solicitud estaba bloqueada.

## Alcance que permanece pendiente

Este bloque no sustituye `add_vet_patient_event`, las políticas de eventos, las rutas de expediente/formularios, agenda, las consultas agregadas de dashboard, recetas ni exportaciones. Algunas aún usan roles antiguos y pueden devolver información de pacientes por otras rutas. Por tanto, las pruebas de RLS de estas dos tablas NO acreditan aislamiento de todo el producto ni autorizan una beta clínica.

La UI y la cola offline deberán consumir permisos efectivos del servidor en el corte coordinado. Hoy la interfaz anterior puede ocultar una acción permitida o mostrar una acción que este candidato rechazará; no desplegar el SQL aisladamente. No se añadió un OR de compatibilidad con roles antiguos.

**Aplicar el candidato cambiaría estas tres rutas inmediatamente, aunque `permission_policy.enforcement_enabled` siga falso.** El indicador global queda desactivado porque no se ha completado la revisión del resto del sistema. Esta entrega solo guarda y prueba el candidato; no contiene operador ni paso de despliegue remoto.

## Fases y riesgos

1. Este bloque: autorización administrativa de pacientes/tutores y pruebas de alta/lectura. Riesgos de elevación por rol, lectura implícita y revocación concurrente cubiertos en aislamiento local.
2. Agenda y agregados: eliminar lecturas por roles y evitar que dashboards/buscadores expongan áreas sin permiso.
3. Expediente y actos clínicos: definir las facultades de cada evento y mantener separadas habilitación, procedimiento y concesión. `patient.write` nunca se toma como autorización genérica para actos clínicos.
4. Integrar hospital/aplicaciones/frascos, recetas/formatos, inventario, Storage/Edge/UI. Comprobar todos los accesos antes de un corte remoto coordinado, sin convertir roles ni crear habilitaciones implícitas.

## Validación reproducible

`bash supabase/tests/run_permission_patient_registration.sh`

El ejecutor reconstruye M2/M4/M5/formularios/M6 y la base de permisos con guardas beta en Docker sin red. Usa exclusivamente identidades, evidencia, pacientes y tutores sintéticos. Ejecuta también la suite previa de la base de permisos.

Casos específicos: admin sin concesión rechazado; rol MVZ con lectura no permite crear; etiqueta MVZ no habilita profesionalmente; auxiliar con permiso administrativo explícito puede crear; escritura no implica lectura; lector autorizado consulta pacientes/tutores; otras clínicas no ven sus filas; anon no ejecuta/lee; reintento devuelve la misma entidad; cambio de payload se rechaza; revocación posterior impide reintento; auditoría conserva concesión y autor; revocación que gana el bloqueo y vencimiento durante espera impiden crear pacientes. Sin activación de banderas globales.

Resultado local: satisfactorio, incluidas las dos pruebas con sesiones concurrentes. No se ejecutan pruebas Flutter porque esta entrega solo cambia SQL candidato, pruebas y documentación; no modifica la aplicación.

La acción manual `test-permission-cutover.yml` solo ejecuta estas pruebas aisladas; no recibe secretos Supabase ni aplica migraciones.
