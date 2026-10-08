# M2: acceso offline y base de sincronización

## Disponible ahora

Sembast guarda el estado en un archivo del directorio de soporte de la app en
Android/iOS y en IndexedDB en web. Room queda sustituido por almacenamiento
multiplataforma. Preferencias visuales siguen en shared_preferences.

Se guarda únicamente el resumen de membresías consultado en Supabase: usuario,
clínica, nombre, rol y momento de verificación. No se guardan aquí contraseñas,
propietarios, fichas médicas del personal ni expedientes.

El acceso guardado requiere una identidad restaurada por Supabase y una caché
con menos de 24 horas. No permite crear una identidad ni elegir un rol offline.
Ese límite se verifica con el reloj local, no es una garantía de revocación inmediata
sin conexión. Un reloj anterior a la última verificación invalida la caché.

Solo errores de transporte/timeout permiten recuperar la caché. Rechazos de permisos,
roles desconocidos o datos corruptos bloquean acceso. Al recibir datos nuevos del
servidor, una clínica retirada deja de ser accesible. El intento de verificación se
repite cada 30 segundos mientras la app está activa; hay botón de reconexión.

La gestión de cuentas, clínicas, invitaciones y miembros exige conexión. Cerrar sesión
limpia el acceso guardado y la cola del usuario cuando no hay cambios pendientes.
Si existen cambios pendientes/conflictos, bloquea el cierre para no descartarlos.
Un cierre externo de sesión impide acceder al ámbito anterior; la cola queda separada
por usuario para no mezclar trabajo. Los módulos futuros necesitan una UI de revisión
antes de habilitar edición offline con cambios sensibles.

## Cola preparada

`SyncEngine` usa adaptadores registrados explícitamente. En producción todavía no
hay adaptadores de datos: no se envía ningún expediente/producto a un endpoint
inventado. El núcleo recibe el motor por constructor. Tras verificar membresías,
se intenta procesar la cola de cada clínica autorizada.

Cada operación conserva usuario, clínica, tipo, registro, versión esperada, acción,
payload e identificador de operación. Encolar requiere identidad actual, permisos
de un resumen vigente (solo si el adaptador admite edición offline) o permisos
consultados online. Antes de cada envío se vuelve a consultar la membresía real.

- Orden de inserción persistido y particiones por usuario/clínica.
- Reintento de transporte con espera creciente; no se elimina una operación sin ACK.
- Conflictos de versión y errores de autorización quedan para revisión.
- No se procesan operaciones posteriores del mismo registro bloqueado/en conflicto.
- Un motor no hace dos procesamientos simultáneos.
- Un identificador ya pendiente no puede reutilizarse con otro contenido.

Cada backend de módulo debe implementar RLS, escritura atómica con versión esperada,
recibo persistido por identificador de operación y control de payload. El recibo es
lo que evita duplicar un cambio si el servidor lo aplicó y se perdió la respuesta.
La prueba actual usa un adaptador simulado con esas propiedades; aún no existe un
backend real para operaciones de expedientes/inventario. No implica sincronización
completa de clínica ni resuelve automáticamente los conflictos.

## Datos sensibles

La base local actual no añade cifrado a Sembast. Está limitada a metadatos de acceso;
no habilitar caché de datos sensibles sin definir cifrado, consentimiento, permisos,
retención y eliminación específicos. Cada futuro módulo registrará únicamente sus
adaptadores aprobados; tipos no registrados se rechazan antes de persistir en la cola.
El usuario solicitó dejar las pruebas reales de registro y acceso para el final.

## Verificación

21 pruebas Flutter: originales más casos de offline, aislamiento, caducidad,
rechazo de permisos, logout con pendientes, identidad, persistencia en archivo,
reintentos, conflictos, permiso revocado y llamadas simultáneas.
Análisis sin incidencias y compilación web configurada aprobados. Chromium verificó
creación de IndexedDB y persistencia tras recarga, sin errores JavaScript y sin enviar
formularios. Validar módulos
con datos reales y dispositivos Android/iPhone sigue pendiente.
