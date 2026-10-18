# Incidencias de la prueba en teléfono — 18 octubre

La usuaria confirmó perfil/clínica, agenda, inventario y escáner. Caja,
estadísticas, cálculos, equipo/avisos y exportaciones siguen sin verificar.
Reportó buscador no visible, fallo al guardar paciente, selector vacío de ingreso,
guardado de zona horaria y pantallas de formatos/receta. Las dos capturas finales
recibidas corresponden al membrete y a la configuración de checado.

## Causas y correcciones

- Zona horaria: el diagnóstico 39123128256 reprodujo SQLSTATE 23502 porque
  `inv_settings` omitía `audit_log.entity_id`. 14C aporta el ID de clínica;
  mantiene el NOT NULL y las autorizaciones, con guarda de hash para reemplazar
  solo la definición revisada. Aplicación 39123718264 aprobada.
- Pacientes: el servidor aceptó altas sintéticas sin tutor y con tutor. Todas se
  revirtieron. En el cliente, la ruta de captura dependía del modelo de la lista,
  que se elimina durante la revalidación de permisos. Ahora conserva su propio
  repositorio/ámbito y el servidor sigue autorizando cada alta; el borrador y su
  operación idempotente permanecen aunque la lista se reconstruya.
- Ingreso hospitalario: misma corrección de vida del borrador. Lista vacía muestra
  una explicación y deshabilita Registrar ingreso. No se vuelven obligatorios
  jaula, peso o temperatura.
- Buscador: estaba en Inicio, pero la lista principal conservaba el desplazamiento
  del apartado anterior. Se reinicia al cambiar de apartado/rama. La regresión
  comprueba que vuelve a quedar visible al regresar a Inicio. No se recibió captura
  del dashboard: confirmar en teléfono si había otra causa.
- Formatos: al perfil operativo inicial le faltaban `form.template.read`,
  `form.template.edit` y `form.branding.manage`. Perfil v2 agrega solo esos tres,
  sin extender los 26 anteriores ni añadir aprobación profesional. Aplicación
  39123720217 aprobada. Can_approve permanece false.
- Membrete: la entrada consulta `form_branding` y `form_templates_list`; faltaban
  los permisos de plantillas indicados arriba. El diagnóstico posterior confirma
  lectura, edición y membrete habilitados, con ocho plantillas disponibles. Falta
  repetir la apertura y el guardado desde la sesión real del teléfono.
- Checado: `att_qr` exige configuración previa y secreto de QR. La captura muestra
  `attendance_settings_required`, una condición esperada antes de configurar.
  Usar «Ubicación y aviso» con ubicación, radio, precisión y aviso reales de la
  clínica; `workspace.manage` ya está concedido. No se inventaron esos datos ni
  se generó consentimiento por la usuaria. Guardado y escaneo reales pendientes.
- Receta/perfil: capturar una cédula no la verifica. El aviso de habilitación no
  vigente es el resultado esperado, no un permiso que deba eliminarse.

## Evidencia y entrega

[39123859642](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39123859642)
confirmó después del arreglo: ambas altas sintéticas y zona horaria pasan, todas
las escrituras de prueba revertidas, pacientes disponibles 0, plantillas disponibles
8, lectura/edición/membrete permitidos y aprobación false. La ejecución usa un
contexto administrativo, no una sesión Auth HTTP de la persona.

[39123790233](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39123790233)
aprobó análisis Flutter y **55 pruebas**: dashboard, pacientes, hospitalización,
formularios, identidad y navegación. Cubre borradores abiertos durante denegación
provisional y recarga de permisos y la visibilidad del buscador al volver a Inicio.
El primer intento del test hospitalario no incluía `patient.read` en su fixture;
se corrigió la fixture, conservando los requisitos del servidor.

Zona horaria y permisos de plantillas ya están corregidos en servidor. Los
cambios de cliente están incluidos en la compilación 39124259241, aprobada sobre
`ef54c78`. El paquete anterior 39082429107 carece de estas correcciones. Revisadas
las siete capturas, queda repetir en teléfono, incluido membrete y checado.

## Repetición en teléfono

1. Actualizar la aplicación conservando su almacenamiento; comprobar que abre la
   misma cuenta y clínica. Volver a Inicio y verificar el buscador arriba.
2. Crear un paciente ficticio, dejar el formulario abierto durante una recarga de
   acceso y guardar. Verificar que aparece una sola vez y conserva su tutor.
3. Actualizar hospitalización, seleccionar ese paciente e ingresar sin jaula.
   Verificar que jaula, peso y temperatura siguen siendo opcionales.
4. Guardar America/Mexico_City y reabrir para comprobar persistencia.
5. Actualizar Formatos; abrir «Logo y membrete de la clínica», guardar un cambio
   de prueba y comprobarlo al reabrir. Esto no aprueba plantillas ni habilita MVZ.
6. En Checado abrir «Ubicación y aviso», configurar únicamente datos reales de la
   clínica y su aviso aprobado. Después generar QR y probar consentimiento,
   entrada/salida, caducidad y rechazo fuera del radio; verificar exportaciones.

No se declara aprobada ninguna de estas comprobaciones reales por haber pasado
las pruebas automáticas. Caja, estadísticas, cálculos, avisos y exportaciones
continúan pendientes según el reporte de la usuaria.

## Entrega conjunta verificada

[Compilación 39124259241](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39124259241):
análisis sin incidencias y **369 pruebas Flutter aprobadas**. VersionCode
**214486897**, firma propia y verificación de ambos APK aprobadas; registro de
publicación beta completado. No abre admisiones ni concede habilitación MVZ.

[Descarga](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39124259241/artifacts/12135696791):
`vetdosis-pruebas-apks`, ZIP de 31 272 251 bytes, disponible hasta el **1 noviembre
2026, 11:56 UTC**. Extraer el ZIP; ARM64: `app-arm64-v8a-beta-release.apk`
(32.5 MB), ARM32: `app-armeabi-v7a-beta-release.apk` (29.2 MB).

Instalar como actualización sin desinstalar ni borrar datos. Confirmar en teléfono
los pasos anteriores; no se declara resuelta la prueba real del membrete hasta
que la usuaria vuelva a abrirlo con los permisos actualizados.
