# Candado beta — etapa 1

## Alcance y estado

Implementación: políticas privadas 60/7/14/90, inscripción por correo aprobado o invitación de un uso, términos versionados, publicación inmutable de builds, patrocinio por clínica, guardas y panel de plataforma con 2FA. No habilita admisiones ni reemplaza la migración de permisos profesionales pendiente.

El flujo `Preparar beta cerrada en Supabase de pruebas` aplica únicamente 09A + 09B al proyecto fijo de pruebas, comprueba el hook existente antes de modificarlo y mantiene `admissions_enabled=false` y `enforcement_enabled=false`. La app muestra «Pruebas internas · admisiones beta cerradas» mientras sigue ese estado. No equivale a una beta ya restringida a invitadas; las cuentas internas conservan el acceso anterior hasta la apertura revisada.

## Esquema aplicado por esta etapa

- 09A: administradoras de plataforma separadas, correos aprobados, invitaciones con hash, inscripciones únicas, términos y auditoría privados.
- 09B: publicaciones beta, política de versión mínima, relación build/sesión, patrocinio de espacio y eventos de pérdida. Guardas de escritura en tablas de aplicación y Storage; política restrictiva de lectura de objetos y hook REST.
- Cuenta de plataforma: matrícula administrativa fuera de la app de una cuenta **ya registrada y con correo confirmado**. No crea una contraseña, no envía correo ni convierte al dueño en MVZ. Nunca puede agregarse como miembro de una clínica mientras esté habilitada como administradora.
- El servidor exige `aal2` para cada RPC administrativo. Inscribir un factor sin completar el desafío no concede acceso. El panel permite aprobar/revocar correos, crear/revocar invitaciones y ver inscripciones; no tiene botón para abrir la beta.
- Solo se muestra el token original al crear una invitación. Los listados no contienen token ni hash. Vigencia elegida en el panel: 24 horas.
- Builds: caducidad a 90 días desde publicación con hora de servidor; la misma versión no puede rejuvenecerse. CI registra una publicación después de verificar ambos APK y subir sus artefactos.
- Una versión declarada por el cliente sirve para compatibilidad, no demuestra la autenticidad del APK. La autorización se basa en Auth, inscripción y permisos. Storage utiliza la relación build/sesión cuando no recibe el encabezado del cliente.
- Gracia del patrocinador: 14 días desde pérdida registrada, revocación o vencimiento del patrocinador, sin renovar la inscripción del miembro. Aceptar otro patrocinio requiere beta vigente y administración de esa clínica.

## Rutas cubiertas y límites antes de abrir

- REST: el hook comprueba la inscripción antes de invocar endpoints antiguos, incluidas funciones `SECURITY DEFINER` que no dependen de RLS.
- Escrituras: triggers comprueban el estado individual y, cuando la fila tiene clínica directa, el patrocinio. Se conserva la autorización propia de cada endpoint.
- Storage: guardas de escritura y política restrictiva de lectura, además de las políticas existentes de propietario/clínica.
- Edge Functions: se comprueba el JWT del llamador y el estado beta antes de trabajos con credencial de servicio o gasto externo. Lectura de PDF ya emitido permanece permitida; generar uno nuevo requiere escritura y clínica autorizada. Solo se despliegan las funciones ya autorizadas; preparar código para las demás no acredita su despliegue.
- Exportación operacional: se permite su anotación específica de auditoría al estar en consulta/exportación; no se abre escritura general en bitácora.
- Migraciones siguientes: volver a ejecutar `private.beta_install_guards()` para tablas nuevas y auditar los alcances indirectos (artefactos/cuotas/relaciones) con el modelo profesional antes de activar el candado. No se acredita cobertura completa solo por contar triggers.
- Las tareas privilegiadas del servidor y webhooks conservan su canal de servicio. El secreto no está en Flutter. Deben revisarse los endpoints desplegados y sus permisos antes de apertura.
- Offline: no se concede un acceso beta nuevo sin comprobación del servidor. Un error de verificación bloquea la pantalla y conserva el borrador de la sesión; las escrituras offline y sincronización clínica siguen pendientes de la fase correspondiente.
- La interfaz de consulta/exportación muestra un aviso; la autorización efectiva de guardar se valida en servidor. Queda revisar la desactivación visual de cada formulario durante la migración de permisos.

## Términos y conservación

`docs/beta-terminos-borrador.md` es una propuesta para revisión, no una versión publicada. No se insertan términos ficticios en remoto ni se aceptan por el usuario. Falta aprobar el texto y completar la identidad/contacto del aviso de privacidad. Al vencer no se borran datos automáticamente; se conserva la decisión de definir el borrado después.

## Pruebas

- `bash supabase/tests/run_beta_foundation.sh`: admin separado, MFA, ACL, normalización, revocación y límites temporales.
- `bash supabase/tests/run_beta_gate.sh`: inscripción, hash/términos, correo verificado, invitación ligada al correo, reintento sin renovar, versión desconocida, vencimiento, bloqueo de RPC/Storage, lectura, revocación, patrocinio/gracia y conservación.
- `flutter test test/beta_boundary_test.dart`: admisiones cerradas, aceptación explícita, consulta/exportación, 2FA y conservación de borradores ante fallo de conexión.
- `python3 -m unittest discover -s scripts/supabase -p 'test_*.py'`: despliegue acotado, hook ajeno no sobrescrito y preparación sin apertura.
- `deno check` con la configuración de imports de forms-pdf para las cuatro funciones con acceso del usuario; pruebas del generador PDF existente.
- Pendiente real: MFA en la cuenta de plataforma, términos aprobados, dos cuentas/dos clínicas y pruebas HTTP autenticadas de Storage y Edge Functions con el candado activado en un entorno controlado. La concurrencia de inscripción se comprobó con dos sesiones PostgreSQL paralelas: una inscripción, una invitación consumida y sin renovar el plazo. Falta repetir los escenarios HTTP con sesiones Auth reales.

## Orden restante

1. Registrar/confirmar la cuenta separada si aún no existe; completar 2FA desde el APK nuevo.
2. Revisar términos/privacidad.
3. Migrar permisos por persona y procedimiento y habilitación con evidencia, sin promociones automáticas.
4. Cerrar cobertura de todas las rutas y pruebas de aislamiento/concurrencia/vencimiento.
5. Publicar términos y versión mínima; abrir admisiones solo después de esos pasos.
