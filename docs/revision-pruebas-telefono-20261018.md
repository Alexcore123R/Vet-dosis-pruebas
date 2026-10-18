# Incidencias de la prueba en teléfono — 18 octubre

La usuaria confirmó perfil/clínica, agenda, inventario y escáner. Caja,
estadísticas, cálculos, equipo/avisos y exportaciones siguen sin verificar.
Reportó buscador no visible, fallo al guardar paciente, selector vacío de ingreso,
guardado de zona horaria y pantallas de formatos/receta. Faltan dos capturas que
la usuaria anunció; no cerrar esos hallazgos sin revisarlas.

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
  comprueba que vuelve a quedar visible al regresar a Inicio. La captura pendiente
  del dashboard puede revelar otro caso y todavía debe revisarse.
- Formatos: al perfil operativo inicial le faltaban `form.template.read`,
  `form.template.edit` y `form.branding.manage`. Perfil v2 agrega solo esos tres,
  sin extender los 26 anteriores ni añadir aprobación profesional. Aplicación
  39123720217 aprobada. Can_approve permanece false.
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
cambios de cliente todavía no están en un nuevo APK: el paquete anterior
39082429107 carece de estas correcciones. Pendientes las otras dos capturas para
completar la revisión y empaquetar una entrega conjunta; después repetir en teléfono.
