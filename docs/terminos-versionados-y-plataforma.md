# Términos versionados y administración profesional

16-oct-2026. Continuación de permisos 2A. Sin apertura de beta ni verificación profesional automática.

## Fuentes de Drive

- [Términos de la prueba, borrador v1](https://docs.google.com/document/d/1-hUUWhqMbcaUqbX02M9NTlowFTLIpfUP20Cp4vD-ifw/edit?usp=drivesdk).
- [Aviso de privacidad, borrador v1](https://docs.google.com/document/d/1RNUffKxIYnZmOIgGSPRM3IQztVszzqxxXe4_Jiyp-30/edit?usp=drivesdk).

Copias de origen en `docs/legal/terms-v1-drive.json` y `privacy-v1-drive.json`, con URL, identificación, fecha de modificación y versión exactas. Se conserva el contenido de origen, incluido su estado de borrador. No se modificaron los documentos de Drive. El importador solo carga el texto de términos como borrador no publicado; el aviso de privacidad permanece como fuente para completar, sin afirmar que ya se muestra o acepta en la app.

## Estado y pruebas

- Implementado localmente: número de versión visible junto al texto, envío de esa versión/hash exactos, historial inmutable `public.terms_acceptances`, aceptación de actualizaciones sin renovar la beta, consulta/exportación si no se acepta una actualización y conservación de capturas en curso.
- Ya existía: `beta_enrollments` conservaba versión/hash de la primera inscripción. Se mantiene ese registro inicial; no se reemplaza por la última aceptación.
- Preparado para remoto: migraciones 12A/12B, importación de borrador y operador que exige dependencias y beta cerrada. El resultado remoto se registra al terminar el flujo.
- Pendiente: completar y revisar los textos legales, publicarlos por una operación distinta y completar la migración de permisos por módulo antes de abrir beta.

## Aceptación coherente

`terms_acceptances` guarda usuario, versión, hash, fecha del servidor y origen de la aceptación. Clave única usuario/versión y FK a la versión/hash del texto. RLS permite leer solo el historial propio; no hay INSERT/UPDATE/DELETE de cliente. Actualizar o eliminar una aceptación está bloqueado; se anexa otra fila para otra versión.

La migración conserva aceptaciones antiguas solo si su texto publicado y hash original se pueden comprobar; mantiene fecha y versión originales y marca origen de migración. Ante una inscripción histórica sin texto comprobable, se detiene para revisión. No inventa aceptaciones de documentos nuevos.

El servidor valida versión actual, publicación y SHA-256 del contenido antes de registrar. Un texto anterior o hash distinto se rechaza. El cliente muestra la versión tomada de la misma respuesta que contiene el texto; cambiar versión o hash desmarca la casilla. Si el texto cambia mientras se acepta, se carga la versión nueva y se pide una nueva confirmación.

`beta_accept_terms` sirve para personas ya inscritas: no consume otra invitación, no crea una inscripción, no modifica los 60 días, no revive una revocación ni convierte un build vencido en vigente. Puede aceptar términos con la beta vencida, conservando el modo consulta/exportación. El historial conserva todas las versiones aceptadas. No se añaden IP, huellas de dispositivo ni datos adicionales no solicitados.

Cuando haya una nueva versión publicada y el candado esté activo, las escrituras quedan bloqueadas hasta aceptarla. Las lecturas/exportaciones siguen sujetas a los permisos existentes. La excepción de escritura se limita al registro legal autenticado del propio usuario; no permite modificar datos de la app. Reinstalar las guardas de tablas conserva esta excepción acotada.

## Pendientes concretos de los borradores

1. Completar responsable, contacto, domicilio y ciudad/estado en Drive; no se sustituyen con nombres o domicilios supuestos.
2. Alinear el punto 6 de términos y el punto 5 del aviso con la decisión de la propietaria: **por ahora conservar los datos y definir el borrado después**. El borrador menciona borrado y `[30]` días; no se implementa esa política ni se publica ese texto.
3. Confirmar proveedores, región, registros técnicos y permisos del teléfono con el funcionamiento real; completar los campos marcados «confirmar» sin inventar normas ni plazos.
4. Revisar la cobertura del aviso para identidad y evidencia profesional, y el momento en que el aviso se presenta respecto al registro de cuenta. No afirmar que el borrador ya describe todo el tratamiento de datos de la app.
5. La publicación deberá usar texto final, sin marcadores ni estado de borrador, con número explícito y hash congelado. Una versión ya publicada no se sobrescribe aunque se edite posteriormente el documento de Drive.

Propuesta para alinear el borrado, pendiente de incorporarse al texto final: al vencer se mantiene consulta y exportación; no hay eliminación automática por vencimiento en esta etapa. La política definitiva y el procedimiento de solicitudes se comunicarán mediante una versión posterior revisada. Esto no define un plazo normativo ni altera obligaciones de conservación.

## Avance de permisos: plataforma

La pantalla «Habilitaciones profesionales globales» se ofrece dentro de administración de plataforma tras 2FA. Permite consultar revisiones globales ya registradas y revocarlas con motivo y confirmación. No contiene botón para verificar al primer MVZ: esa revisión permanece fuera de la app, con evidencia real.

Nuevos RPC `platform_beta_professional_list` y `platform_beta_professional_revoke`: ambos exigen cuenta de plataforma separada y JWT aal2 en cada operación. La ruta funciona bajo el hook beta activo sin inscribir al administrador como usuario clínico. La excepción del trigger se limita a anexar una revocación global por plataforma con MFA; no autoriza escrituras clínicas ni cambia membresías.

Un administrador de clínica no accede a esta consola por su rol. La lista excluye verificaciones locales. La evidencia no se muestra después de un fallo de actualización de la sesión. Revocar una revisión no borra su registro ni genera otra habilitación.

Sigue pendiente la sustitución de ACL por módulo, la vinculación de procedimientos/concesiones a aplicaciones y frascos, la autorización ordinaria y el acto real en PDF, y las pruebas Auth reales de dos clínicas. Consultar [inventario del corte](diseno/corte-permisos-pendiente.md). Esta entrega resuelve el recorrido de revocación global bajo el hook; no acredita el corte completo.

## Validación

- PostgreSQL aislado: migración de aceptación histórica, primera admisión, rechazo de versión/hash antiguos, historial propio e inmutable, actualización sin renovar prueba, expiración, reinstalación de guardas y digest exacto del borrador de Drive con Unicode/BOM/CRLF.
- PostgreSQL con candado activo: consulta/revocación global con plataforma aal2 sin inscripción clínica; rechazo aal1/anon/admin de clínica; ausencia de endpoint público de primera verificación; revocación idempotente.
- Flutter: número visible igual al enviado, renovación de consentimiento, cambio de versión aun con hash igual, recuperación tras cambio del texto, consulta/exportación, conservación del borrador y consola móvil de plataforma.
- Operador: inspección sin cambios, confirmación, beta cerrada, esquema parcial y protección contra reemplazar una versión publicada con un borrador.
- Pendiente real: publicación del texto final aprobado y prueba del consentimiento desde cuentas reales. No se acepta ningún texto en nombre de usuarios.

## Evidencia remota, 16-oct-2026

- Preparación correcta: https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38838576839. Aplicadas 12A/12B en una transacción; origen versión 1 importado como borrador. Postflight verdadero: beta cerrada, contenido/hash exactos y sin publicar, API de aceptación y revocación de plataforma disponibles.
- Pruebas reales HTTP sin sesión: `beta_accept_terms`, `platform_beta_professional_list` y `platform_beta_professional_revoke` devolvieron 401 / SQLSTATE 42501. No se usaron sesiones ni contraseñas de usuarios para esas comprobaciones.
- 259 pruebas Flutter de la suite completa, sin observaciones del analizador; 27 pruebas Python y suite PostgreSQL aislada correctas, repetidas en el flujo remoto antes de preparar.
- APK iniciado en https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38838577172. Su resultado se registrará al terminar la verificación de firma y publicación del artefacto.
- No se publicaron términos, no se creó una aceptación ficticia, no se verificó a ningún MVZ ni se cambiaron las fechas de una beta. Las pruebas que insertan aceptaciones usan cuentas y textos sintéticos en Docker aislado.
