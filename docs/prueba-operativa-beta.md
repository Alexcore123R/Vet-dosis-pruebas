# Prueba operativa completa por etapas

La titular eligió probar todas las funciones con datos ficticios. El perfil
`operational_beta_v1` concede por persona, a la titular de una sola clínica de
prueba, 26 permisos no profesionales y no ligados a un procedimiento. Concesiones
nuevas: 60 días desde el servidor. Las vigentes se conservan sin extenderlas.

El administrador del proyecto ejecuta la configuración solicitada por la titular
mediante el RPC de concesión existente y un contexto administrativo transaccional
en su nombre. No se afirma que haya habido un inicio de sesión Auth de esa
persona. La bitácora registra tanto las concesiones como un evento separado
`beta_operational_setup`, con origen de automatización, actor de GitHub y ejecución.
Esto no sirve como prueba HTTP con una sesión real.

No crea esquemas, roles, habilitaciones, tipos de procedimiento, órdenes ni datos
clínicos. Exige titularidad/admin y cuentas separadas; rechaza cambios del catálogo
que vuelvan profesional o por procedimiento cualquiera de los permisos previstos.
El modo predeterminado termina en rollback. La beta global permanece cerrada.

## Recorrido con datos ficticios

- Perfil, identidad, logo, apariencia, buscador, menú y guía de inicio.
- Pacientes y agenda: alta mínima, edición, búsqueda y cambios de cita.
- Inventario: catálogo/lotes, ajustes auditados, búsqueda y escáner con teléfono.
- Caja: apertura, venta de productos no sujetos a receta, pagos, cortes y reversos.
- Dashboard: cifras coherentes, avisos, recarga, y visibilidad al revocar permisos.
- Hospitalización: admisión/ubicación y observaciones opcionales; sin órdenes ni
  altas clínicas autorizadas por una cuenta no habilitada.
- Preparación de documentos/recetas y consulta del expediente según condiciones
  del servidor; firma y autorización requieren sus comprobaciones vigentes.
- Cálculos: vectores ficticios conocidos y referencias sin verificar identificadas;
  ningún resultado se usa para decidir o aplicar un tratamiento.
- Exportación y respaldo: comprobar integridad y pertenencia. La restauración
  aislada/staging sigue pendiente de integración; no restaurar sobre la clínica.

La validación positiva de prescripción, actuaciones clínicas por procedimiento,
medicación, frascos/controlados y reportes profesionales necesita un MVZ con
habilitación y los permisos correspondientes. Para la cuenta no habilitada debe
comprobarse el rechazo: esto también forma parte de probar la función.

Comprobar por separado en teléfono: cámara, permisos Android, impresión/PDF,
compartir, notificaciones con app cerrada y anticipación. La instalación de
concesiones no acredita esos resultados. IA/Edge/13Y, 13X Storage, modo offline y
flujos pendientes se mantienen como pendientes hasta sus pruebas/despliegue.
No anunciar todas las funciones aprobadas con solo terminar este perfil.

## Aplicación verificada — 18 octubre, 08:18 UTC

[39110855603](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39110855603)
aprobó 74 pruebas Python, el perfil completo sobre PostgreSQL aislado y el ensayo
con rollback en el proyecto real de pruebas; las concesiones seguían vacías.
[39110925396](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39110925396)
aplicó después las 26 concesiones y comprobó que todas son efectivas para la
titular indicada por la usuaria en una sola clínica (`vet prueba1`). La habilitación
profesional siguió falsa. Bitácora y origen administrativo registrados. No se
modificaron datos clínicos ni concesiones ajenas, ni se abrieron admisiones.

El APK vigente de revisión sigue siendo 39082429107, con 365 pruebas aprobadas;
esta configuración de servidor no exige otro APK. Se requiere ese APK corregido
y recargar la sesión para consultar el contrato de módulos nuevo. La comprobación
positiva con una sesión Auth real y la prueba en teléfono siguen pendientes: el
éxito de la configuración administrativa no las sustituye.

## Complemento de plantillas — 18 octubre

39123720217 aplicó el perfil operativo v2: agrega consulta, edición de versiones y
membrete de plantillas (29 códigos previstos en total). Conserva las concesiones
anteriores sin extenderlas, y no concede `form.template.approve` ni habilitación.
La revisión 39123859642 confirmó 8 plantillas consultables y aprobación false.
Véase `revision-pruebas-telefono-20261018.md` para las incidencias y su validación.
