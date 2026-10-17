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
