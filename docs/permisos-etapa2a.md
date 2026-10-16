# Permisos y habilitación: etapa 2A

16-oct-2026. Implementa la base del esquema beta-permisos v1.1 aprobado. No es la sustitución completa de las ACL heredadas y no permite abrir la beta.

## Estado y alcance

- Implementado y probado localmente: registro de evidencia, puesto visual, tipos de procedimiento, concesiones por persona/clínica, revocaciones, designación del responsable con aceptación propia y pantalla móvil. No se convierten roles ni autorizaciones profesionales antiguas.
- Preparado local: `supabase/proposed/11A_permission_foundation.sql`, ejecución acotada y pruebas aisladas; repositorio privado y compilación de APK por Actions.
- Aplicado remoto: registrar el resultado del flujo al terminar. La base se aplica desactivada, sin verificaciones, concesiones ni procedimientos de ejemplo.
- Pendiente antes de abrir beta: reemplazar ACL de RPC/RLS/Storage/Edge/UI por módulo, ligar procedimiento/concesión a aplicaciones y tomas, flujo de autorización ordinaria con acto real en PDF y pruebas Auth reales de dos clínicas. No atribuir cobertura de estas rutas a las pruebas de la base.

## Modelo implementado

Todas las nuevas tablas están en `private`, con RLS habilitada y sin permisos de tabla para anon/authenticated. Los RPC devuelven proyecciones por membresía; administración clínica conserva únicamente su función administrativa en esta etapa. El puesto no afecta la evaluación de ninguna facultad.

- `permission_policy`: desactivada y revisión de migración falsa. No hay RPC de activación. No se puede habilitar sin revisión, ni a través del despliegue de esta etapa.
- `permission_catalog`: códigos técnicos versionados; no contiene dosis ni protocolos. `procedure.perform`, `drug.administer` y `vial.draw` exigen un tipo explícito de la misma clínica. No se admite comodín.
- `member_job_labels`: etiqueta visual editable, sin copiar puestos antiguos ni modificar roles existentes.
- `procedure_types`: nombres de alcance definidos por clínica; inactivar un tipo deja sus concesiones sin efecto.
- `member_permission_grants` y `permission_revocations`: registros anexados con otorgante, fecha servidor, vencimiento, motivo y tipo de procedimiento. La fecha de membresía se conserva para que salir y volver a entrar no reactive concesiones. No se deducen permisos a partir de una cédula.
- `professional_verifications` y `professional_revocations`: revisión con identidad de revisor, fecha, SHA-256, referencia privada y vigencia elegida. Registro inmutable; revocación anexada. Los perfiles capturados siguen siendo datos sin verificar. La revisión requiere una versión actual con cédula capturada y queda ligada a ella; cambiar nombre o cédula deja de cumplir los datos revisados. No se imprime ni acredita título por estos RPC.
- `clinic_responsible_designations`: el admin propone a una persona habilitada; ella acepta desde su sesión. Caduca y se revoca; salir/reingresar no restaura la designación anterior.

Las facultades reservadas comprueban habilitación vigente por separado. Una concesión no convierte al destinatario en MVZ. Conceder `drug.administer` tampoco permite emitir recetas, dispensar ni validar controlados.

## Primer MVZ y evidencia

El arranque se registra exclusivamente por `private.professional_record_external`, sin EXECUTE para anon/authenticated y sin botón de verificación inicial en la app. Requiere revisor de plataforma separado y habilitado, versión vigente de perfil con cédula, fecha real de revisión, hash SHA-256 del archivo revisado, referencia privada y vigencia explícita. No se crean registros de evidencia con ejemplos ni se da por verificada una cédula al aprobar el acceso beta.

La operación privilegiada la realiza administración después de revisar evidencia fuera de la app. No se pide contraseña, código 2FA ni clave de servicio en el chat. Si falta un dato de evidencia, se deja pendiente. El primer MVZ aún no está verificado por esta entrega.

Luego el responsable aceptado y habilitado puede registrar revisiones para otras personas de su clínica. Nunca puede verificarse a sí mismo ni crear una habilitación global. El admin de clínica sin habilitación no revisa cédulas. La verificación global solo se revoca por plataforma con MFA; la clínica no puede quitar ni alterar la evidencia global. La evidencia se consulta únicamente por sujeto o responsable dentro de su alcance y no entra en respaldos/exportaciones clínicas.

## Pantalla móvil

En «Mi cuenta y clínicas» → «Permisos y habilitación». Cada integrante puede consultar sus datos; el admin puede editar puesto, registrar/inactivar tipos, otorgar/revocar permisos y proponer responsable. El responsable acepta desde su propia cuenta y gestiona revisiones de otras personas con evidencia. Se muestra que las concesiones están en preparación hasta completar la migración.

Vigencia, procedimiento y motivos no tienen valores clínicos preseleccionados. Se presenta resumen antes de guardar. Un error de consulta elimina controles basados en datos previos. Requiere conexión y membresía vigente; no se permite administrar desde caché offline.

## Riesgos y siguiente etapa

Los roles heredados siguen operando en las rutas anteriores hasta el corte coordinado. No son un respaldo de permisos nuevos ni una comprobación alternativa: no se añade un OR de rol antiguo al evaluador nuevo. Tampoco se cambia `rx_professional` en este paso: es un cambio posterior que debe probarse junto con recetas, emisión, hospitalización y formularios.

Orden de corte: inventario de dependencias → pacientes/agenda → hospital/aplicaciones/frascos → recetas/formatos/controlados → inventario/operación/respaldos → Storage/Edge/UI. Cada RPC, política y ruta debe sustituirse explícitamente y probarse antes de marcar `migration_reviewed`. Conservar documentos originales, hashes e historia. No desplegar un cambio global de `has_clinic_role` que altere administración o produzca permisos implícitos por contexto.

Las transferencias, restauración y catálogo global de controlados continúan fuera de esta etapa conforme al orden aprobado. No hay borrado por vencimiento de beta.

## Validación

- `bash supabase/tests/run_permission_foundation.sh`: PostgreSQL aislado, dependencia real M6 y guardas beta; solo cuentas y evidencia sintéticas. Incluye ACL de tablas/RPC, aislamiento entre clínicas, autoverificación, aceptación propia, concesión por tipo/acción, identidad revisada, revocación, expiración y no restauración de permisos al reingresar.
- `flutter test test/permission_screen_test.dart`: estado de preparación, ausencia de facultades por puesto, separación del admin/miembro, alcance obligatorio, vigencia/motivo/confirmación y limpieza tras fallo.
- Pruebas Python del operador: inspección sin cambios, confirmación, dependencias, beta cerrada, esquema parcial y no reaplicar una instalación completa.
- Pendiente real: primer expediente de evidencia revisado y pruebas de extremo a extremo con Auth real, realizadas por quienes mantienen sus propias sesiones.
