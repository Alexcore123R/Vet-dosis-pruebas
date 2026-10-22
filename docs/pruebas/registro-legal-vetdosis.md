# Alta de cuenta con aviso de privacidad y términos

## Hallazgo inicial
Antes de esta propuesta, `AuthScreen` llamaba `AuthRepository.register` sin mostrar términos ni aviso. El flujo `BetaBoundary` sí presenta documentos publicados y exige dos selecciones al **inscribirse en la beta** o aceptar una actualización. Esa aceptación se guarda con identidad, versión, hash y fecha del servidor; no equivale a aceptación al crear la cuenta.

## Propuesta de interfaz (PR separada)
- Al pulsar **Crear cuenta**, la app llama `beta_registration_legal` en Supabase **antes de solicitar** registro a Auth.
- El RPC anónimo devuelve exclusivamente la versión **publicada** de términos unida a su aviso **publicado**, con hashes SHA-256. Nunca expone borradores.
- Aparece un diálogo con ambos textos completos consultables, versión visible, una casilla independiente para cada documento, **Cancelar** y **Aceptar y crear cuenta**. No permite continuar con una sola selección.
- Antes de enviar el alta, vuelve a consultar las versiones; si la publicación cambió, exige volver a leer y aceptar las nuevas. Si no hay textos publicados, falla la red o la función no está instalada, **no crea la cuenta**.
- El flujo existente envía correo de confirmación. La evidencia de aceptación autenticada se conserva en `BetaBoundary` al confirmar correo e inscribirse a la beta; el diálogo previo **no se registra** como una aceptación definitiva por parte de un usuario todavía no autenticado. No rellenar un consentimiento a partir de metadatos enviados por el cliente.
- Google OAuth sigue desactivado en la beta probada; antes de habilitarlo, exigir el mismo control a nuevas cuentas OAuth.

## Requisitos previos a distribuir
1. Terminar revisión editorial y jurídica de los textos de términos y privacidad; actualmente figuran como **borradores** y no se deben publicar automáticamente. Confirmar finalidades, responsables y tratamiento real con el área jurídica.
2. Confirmar instalación de 12A y 12C en el Supabase de pruebas. Revisar un respaldo reciente antes de aplicar 12D. El SQL 12D no elimina datos ni modifica tablas, pero **no se ejecutó remotamente**.
3. Publicar el par legal final por el operador autorizado que proteja la versión/hash. No usar las copias de Drive con `state: draft` como textos aceptables.
4. Verificar el RPC con usuario anónimo, sin exponer tablas privadas; probar la pantalla en Honor X6, conexión lenta, cambio de versión entre lectura/confirmación, cancelación y confirmación de correo real.
5. Continuar verificando el recibo de aceptación de `BetaBoundary` con dos cuentas reales en Supabase de pruebas. No interpretar el consentimiento previo al alta como recibo auditado.

La puerta CI usa documentos **sintéticos** y verifica que el API sea de solo lectura. La revisión legal y el despliegue son requisitos separados.

## Pendientes fuera de alcance
- Asociar un recibo autenticado específico al alta de la cuenta, **antes** de la inscripción beta (si se exige esa separación, implementar un RPC de confirmación posterior a email y bloqueo de acceso correspondiente).
- Evitar que futuras altas mediante Google OAuth o enlaces de invitación omitan la presentación previa; aplicar el control cuando se habiliten esas vías.


## Correcciones de revisión — 22 de octubre de 2026

- Se corrigieron los delimitadores SQL mal formados de los cuerpos PL/pgSQL en `12D_registration_legal_preview.sql` y su prueba `registration_legal_preview.sql`; se usan etiquetas de dólar con nombre para evitar ambigüedades.
- La prueba de ruta REST registra ahora `enforcement_enabled=true` **solo dentro de una transacción que se revierte con ROLLBACK**: antes el test esperaba una denegación aunque el candado global estuviera apagado y no se podía demostrar el aislamiento real. Se comprueba la excepción puntual de lectura del aviso y el rechazo de otras rutas.
- `RegistrationLegalDocument.fromJson` verifica también que `SHA-256(UTF-8 del contenido)` corresponde exactamente al hash publicado. Las pruebas agregan un par válido y el rechazo de contenido alterado aunque tenga un hash con formato correcto.
- Revisión de código y tests preparados, **no ejecutados** tras estas correcciones: la cuenta agotó los minutos de GitHub Actions y este entorno no cuenta con Flutter/Docker/PostgreSQL. Se necesita ejecutar `flutter analyze`, `flutter test test/auth_registration_legal_test.dart test/beta_boundary_test.dart` y `bash supabase/tests/run_terms_acceptances.sh` en un entorno con dependencias antes de fusionar o desplegar.
- Sigue faltando confirmar los textos finales y la publicación versionada. **No hay aceptación legal autenticada durante la creación de Auth**: el recibo permanece en la inscripción a la beta después de la verificación de correo; no presentar la ventana previa como recibo final. OAuth/Google exige un flujo equivalente si se habilita.
- No se cambió el Supabase remoto, no se publicaron términos/avisos y no se modificaron permisos ni datos clínicos.
