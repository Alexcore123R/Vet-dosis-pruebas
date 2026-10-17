# Integración de la primera beta conectada

## Alcance

La primera beta requiere conexión para expedientes y aplicaciones. Usa datos
ficticios y comparación de resultados. El motor offline genérico no se presenta
como captura clínica disponible. Las referencias conservan su fuente y estado.
Restauración real, transferencias, cobros activos y publicación Play quedan fuera.

## Inventario antes de aplicar

El workflow **Inspeccionar integración beta (solo lectura)** consulta únicamente
el proyecto `wtrelwtztkddfktrfdpb`. Genera un artefacto JSON con existencia de
objetos, políticas beta/permisos, hook REST y hashes de cuerpos de funciones clave.
Usa el secreto ya configurado en GitHub y no exporta cuentas ni registros clínicos.

`missing` significa que falta la función; `different_definition_requires_review`
significa que requiere comparación; `body_matches_candidate` solo acredita ese
cuerpo. Ningún resultado acredita RLS, grants, triggers o instalación integral.
Por eso el reporte conserva `deploy_ready=false`.

El orden explícito de 23 candidatos esenciales está en
`scripts/supabase/integration_preflight.py`. Incluye 13A–13P y 13W; excluye 13Q–13V
de recuperación. No es un instalador y no ejecuta ningún candidato.

## Paquete atómico preparado

`integration_bundle.py` genera un archivo SQL para revisión. No se conecta al
servidor. El modo predeterminado termina en ROLLBACK; `--commit` genera la variante
de aplicación explícita. Ambos usan el mismo orden y cuerpos de las 23 migraciones.
El workflow de ensayo solo los ejecuta contra PostgreSQL efímero con datos sintéticos.

El paquete detiene la operación si faltan dependencias, si las políticas no están
desactivadas o si detecta funciones nuevas/recibo de una aplicación anterior.
Incluye timeout de bloqueos y de sentencias. Comprueba los hashes de funciones
finales y los conteos de pacientes, tutores, medicación, concesiones y verificaciones.
Guarda un recibo privado con los archivos y hashes al confirmar la transacción;
no genera concesiones ni habilita profesionales o admisiones.

Las pruebas comprueban un error deliberado a mitad del paquete, ensayo con rollback,
instalación parcial, aplicación completa y rechazo de repetición. Esta evidencia
no sustituye revisar el esquema y datos reales ni disponer de respaldo previo.
El paquete no incorpora todavía la actualización de Edge Functions o la prueba
de sesiones reales; no debe usarse como aprobación de apertura de beta.

`integration_dependencies.py` consulta en el servidor la presencia de las mismas
relaciones/funciones exigidas por el paquete. Publica faltantes sin ejecutar DDL.

Antes de aplicarlos hay que comprobar las adaptaciones M2–M14, identidad 10,
fundación beta 09A/09B, permisos 11A y consentimientos/plataforma/privacidad
12A/12B/12C. La presencia de funciones con igual nombre no sustituye esa revisión.
Un esquema parcial se revisa antes de decidir qué falta; no se reejecuta una
migración con CREATE TABLE para intentar repararlo.

## Criterios para desplegar y generar APK

1. Respaldo del entorno de pruebas y lista de diferencias revisada. Beta cerrada,
   sin activar admisiones ni convertir puestos en concesiones profesionales.
2. Aplicación coordinada del esquema y Edge Functions con el cliente compatible.
   Registrar commit, orden y resultado de cada bloque; detenerse ante errores.
3. Verificar primer MVZ por el proceso externo aprobado; permisos concedidos de
   forma explícita para las cuentas de prueba. Cuenta de plataforma separada y MFA.
4. Comprobar HTTP con dos cuentas/dos clínicas y sesión anónima: RPC/tablas,
   Storage, PDF, permisos revocados y vencimiento. Las pruebas locales ya existentes
   no se contabilizan como estas comprobaciones remotas.
5. Confirmar texto/versión/hash de términos y privacidad publicados. Aceptar una
   actualización no renueva la beta; al vencer se conserva lectura/exportación.
6. Generar APK beta firmado conectado al proyecto de pruebas; comprobar versión,
   instalación y prueba en teléfono antes de invitar a otra persona.

## Prueba de aceptación de la app

- Cuenta A crea tutor, paciente y cita ficticios; cuenta B de otra clínica no los ve.
- Una persona con lectura carece de botones de escritura y tampoco puede escribir
  llamando directamente al servidor. Un puesto MVZ no sustituye habilitación.
- Guardar consulta focalizada sin exigir SOAP completo, temperatura, peso ni jaula.
- Preparación de receta, autorización y PDF reflejan a las personas reales y el
  acto de autorización; cada quien aporta su propia firma.
- Hospitalización confirma paciente, fármaco, mg/ml y vía; doble confirmación no
  duplica administración ni extracción. Posponer/no aplicada conservan su significado.
- En Android probar alarma con app cerrada y teléfono bloqueado, y confirmar dentro
  de la app desbloqueada. Comprobar batería, permisos, reinicio y dosis vencida.
- Comprobar cámara, adjuntos, compartir/imprimir PDF, exportación XLSX y rechazo de
  archivos de clínica ajena. Una URL firmada emitida conserva su TTL: no atribuirle
  revocación instantánea de permisos.
- Cortar conexión: explicar la indisponibilidad del registro clínico y recuperar
  acceso al reconectar sin mostrar datos de otra sesión.

La apertura de beta se evalúa después de registrar resultados, fallos y límites
del APK concreto. Esta preparación no abre automáticamente acceso.

## Inspección real del 17 de octubre de 2026

[Ejecución 39029114022](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39029114022)
aprobada, sobre el commit de integración `e31dad7`. Las 36 pruebas Python de
herramientas administrativas pasaron antes de consultar el catálogo remoto.

- Identidad, membresías y las bases de política beta/permisos están presentes.
- Admisiones y enforcement beta están en false; permisos mantiene
  enforcement_enabled=false y migration_reviewed=false.
- El hook REST apunta a `public.beta_request_guard`.
- Diez funciones clave del candidato están ausentes. `clinic_statistics` existe,
  pero su cuerpo difiere del candidato. No se presume que esto describa todos los
  objetos de cada migración.
- No existen las tablas de constantes estructuradas ni staging de restauración.
- Solo se hicieron SELECT de catálogo y políticas; no se cambiaron datos,
  permisos, admisiones o definiciones.

El bloque 13X de Storage clínico, publicado en paralelo desde otra conversación,
se conservó al integrar Git. 5.6 sol corrigió un residuo SQL posterior a COMMIT y
amplió las pruebas. [Storage 39029205418 aprobado](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39029205418).
Permanece como candidato adicional fuera del manifiesto inicial; su aprobación
aislada no acredita instalación remota ni un flujo de adjuntos en la interfaz.

## Ensayo y dependencias del paquete atómico

- Las 42 pruebas Python de herramientas administrativas aprobaron.
- [Inspección remota 39030003970](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39030003970):
  todas las relaciones/funciones exigidas están presentes (`missing=[]`). Esto no
  acredita todavía compatibilidad de definiciones y datos.
- [Ensayo aislado 39030086535](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39030086535):
  aplicación de 23 candidatos, error deliberado y rollback, rechazo de instalación
  parcial/repetida, conteos conservados y hashes finales aprobados.
- La primera ejecución del ensayo falló porque el runner no incluía ripgrep;
  el script usa ahora grep para comprobar sus logs de error esperados.

El artefacto `beta-integration-review-only` contiene SQL de ensayo, SQL candidato
de aplicación y manifiesto de archivos/hashes. No contiene datos exportados ni
credenciales. No se ejecutó el SQL candidato en Supabase remoto.
Faltan el respaldo previo verificado, el ensayo sobre el esquema real y la
coordinación con cliente/Edge y cuentas de prueba antes de aplicar y abrir beta.
