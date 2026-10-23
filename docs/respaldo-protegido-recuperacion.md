# Respaldo protegido y revisión de recuperación

## Implementado localmente

La exportación operacional se cifra por defecto. El usuario elige y confirma una contraseña de al menos 12 caracteres. La app no la persiste ni la envía a Supabase; no hay recuperación de la contraseña por parte de la app. Puede conservarse fuera de ella en un gestor de contraseñas.

Formato `.vetbackup`: AES-256-GCM con nonce aleatorio de 12 bytes, sal aleatoria de 16 bytes, etiqueta de autenticación de 16 bytes y clave derivada mediante PBKDF2-HMAC-SHA256 (600 000 iteraciones, 256 bits). La biblioteca `cryptography` implementa estos algoritmos; no se implementa un cifrador propio. El algoritmo, versión y parámetros admitidos están fijados para impedir que un archivo seleccione arbitrariamente el coste de derivación. Contraseña incorrecta o alteración del contenido provoca rechazo.

Se cifra el archivo completo: snapshot textual original de PostgreSQL, fotos y catálogos. Al abrirlo, se comprueban también los hashes internos y los PDF congelados. El texto original del snapshot se conserva, evitando reconstruir cantidades desde números flotantes. Dos exportaciones del mismo contenido con igual contraseña producen archivos distintos por la sal y el nonce aleatorios.

El trabajo de cifrado/descifrado se ejecuta mediante `compute` fuera del hilo de interfaz en plataformas nativas; en web utiliza el comportamiento de Flutter y de la biblioteca para esa plataforma. No garantiza borrado físico inmediato de copias en la memoria administrada. No se escribe un archivo temporal de respaldo sin cifrar desde este flujo.

Opciones:
- **Respaldo protegido:** activado inicialmente, archivo `.vetbackup`.
- **JSON sin cifrar:** opción explícita; conserva el aviso de almacenamiento restringido.
- **CSV:** sigue siendo un informe sin cifrar, no un respaldo protegido.

Límites: archivo operacional sin cifrar de hasta 50 MiB; contenedor cifrado de hasta 72 MiB por la expansión Base64. El límite se comprueba también sobre el archivo completo, incluyendo sus catálogos. Exportación por lotes y pruebas de memoria en teléfonos siguen pendientes.

## Revisión para recuperación

«Revisar respaldo para recuperación» acepta `.json` y `.vetbackup`. Pide contraseña para un archivo cifrado y después:
1. Verifica estructura, hashes de snapshot/fotos/catálogos y PDF históricos.
2. Exige que la clínica del respaldo coincida con el espacio abierto.
3. Rechaza registros declarados de otra clínica, identificadores repetidos en una tabla y rutas de fotografías fuera de la clínica o con segmentos de recorrido.
4. Muestra fecha, tablas y cantidades de registros; permite guardar un resumen de revisión sin los expedientes ni sus valores clínicos.

El resumen no ejecuta SQL, no importa filas y marca `restored: false`. Hashes y cifrado no acreditan la identidad del emisor. Los formatos clínicos y catálogos de un archivo abierto no se activan automáticamente como fuentes verificadas.

## Restauración de servidor: pendiente de código e integración

El archivo es operacional, no una copia integral de PostgreSQL/Supabase. Excluye credenciales, claves, perfiles reutilizables de firma y fichas médicas ajenas. No permite por sí solo reconstruir todos los usuarios, autorizaciones o servicios. La interfaz continúa indicando que no ha restaurado la base.

Para una restauración real quedan pendientes: recuperación en entorno aislado, comprobación de esquema/versiones y dependencias, correspondencia de usuarios, política de conflictos e identidades, conservación de documentos firmados, auditoría y ensayo de rollback. Requiere además el respaldo integral del servidor y configuración de producción. Drive también continúa pendiente. Este bloque prepara y protege archivos; no presenta esos pendientes como resueltos.

## Pruebas

Cifrado/descifrado conserva los bytes originales, usa resultados aleatorios, rechaza contraseña incorrecta y etiqueta alterada. La inspección rechaza clínica equivocada y filas mezcladas, y no importa registros. Se prueba confirmación/cancelación de contraseña, protección activada inicialmente y ausencia de consulta de estadísticas si el componente se abre con un rol no administrador.

No hay migraciones nuevas ni cambios en Supabase remoto en este bloque.

## Google Drive: exportación manual desde Android

El selector nativo usado por `FilePicker.saveFile` permite elegir ubicaciones
ofrecidas por el proveedor de documentos del teléfono, incluido Google Drive
cuando esté instalado y disponible. Esto **no** enlaza automáticamente una
cuenta Google a VetDosis, no necesita autorización OAuth a Drive por parte
de la aplicación y no programa respaldos sin intervención del usuario.

Después de solicitar `Exportar respaldo protegido`, seleccionar el destino
en el selector de Android y confirmar. Si se cancela, VetDosis informa
`Guardado cancelado`; si el selector devuelve la URI del archivo, informa
solamente que el selector confirmó el guardado. No interpreta esa URI como
prueba de que la copia ya se haya sincronizado remotamente. No muestra ni
guarda la URI, y no solicita permiso global de almacenamiento.

Para validar la copia: buscar el archivo `.vetbackup` en el Drive elegido,
volver a `Revisar respaldo para recuperación`, seleccionar ese archivo,
ingresar la contraseña y comprobar integridad/identidad de clínica.
Esa inspección es de solo lectura y no implica restauración integral del
servidor. No subir JSON ni CSV sin cifrar con datos clínicos a un Drive
compartido. Los respaldos automáticos, el acceso OAuth separado, la
copiadora de PostgreSQL + binarios de Storage y el ensayo de restauración
integral están registrados por separado en el issue #22.
