# Constatación posterior: permisos y firma propia

Candidato 13M, posterior a 13L. No aplicado a Supabase; sin APK ni apertura de beta.

## Estado y alcance

Las rondas hasta 13L están implementadas y probadas de forma aislada. Esta ronda prepara SQL, pantalla y pruebas de constatación posterior de muerte. Ninguna función de esta ronda está aplicada y probada en el servidor remoto. La revisión transversal y la validación real siguen pendientes.

Se conserva el alcance del responsable del consentimiento, sin extenderlo a otras personas. Se añade `clinical.death.record`, por tipo de procedimiento y con habilitación profesional, junto con `procedure.perform` del mismo tipo. No se conceden permisos automáticamente ni se convierten puestos en habilitación. No se añade un catálogo de métodos ni datos clínicos.

## Comportamiento

La lectura exige acceso actual al documento firmado de eutanasia. La captura exige al responsable, habilitación vigente, beta que permita escritura y ambas concesiones vigentes; también comprueba autoridad en la hora observada. El procedimiento debe estar activo en la misma clínica. La hora es posterior a la aceptación del consentimiento y no futura.

Resultado, procedimiento, nombre, hora, método y hallazgos se capturan expresamente. Firma propia y confirmación son obligatorias; no se toma la firma del perfil. Disposición, costo y notas siguen opcionales. La pantalla obtiene capacidades del servidor, no del puesto visual; contratos ausentes/desconocidos fallan cerrados. Cambiar cuenta, clínica, documento o repositorio limpia las capacidades y el borrador. No se requiere peso, temperatura ni SOAP.

`private.death_attestations` guarda identidad, nombre y firma propios, concesiones, procedimiento, versión profesional, hash del contenido y hora del servidor. Tabla privada e inmutable. Las listas muestran nombre/estado de atestación sin exponer vectores de firma. Los históricos no reciben una firma ni permisos inventados.

Los registros y correcciones siguen siendo anexos: motivo y referencia al mismo consentimiento, sin sobrescribir el original. No se cambia el PDF, se registra eutanasia realizada automáticamente ni se cierra hospitalización. El consentimiento firmado no prueba por sí solo la muerte.

La escritura serializa por clínica/identidad/documento, revisa autoridad antes de reutilizar el recibo y conserva la idempotencia. La revocación impide incluso reintentar una operación anterior. Se comprueba vencimiento tras esperar bloqueos.

## Validación

`bash supabase/tests/run_death_attestation.sh` aplica toda la cadena en PostgreSQL aislado y prueba permisos, firma/confirmación, campos explícitos, correcciones, recibos, aislamiento, anon, revocación, concurrencia y vencimiento tras espera. El consentimiento de esta prueba es una fixture sintética de frontera; no acredita firma real de tutor ni ejecución de Edge. Los flujos de firma/PDF anteriores conservan sus pruebas propias.

`test/death_permissions_test.dart` cubre ausencia de autoridad por puesto, elecciones vacías, contrato desconocido y limpieza de capacidades. El workflow manual añade el trabajo `death-attestation`.

Riesgo de despliegue parcial: la pantalla nueva requiere el contrato nuevo. Debe publicarse con el corte coordinado; no hay escritura alternativa por el modelo antiguo. Quedan pendientes las pruebas de Auth/Storage/Edge y teléfono real del conjunto.
