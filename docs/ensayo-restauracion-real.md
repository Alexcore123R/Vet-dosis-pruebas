# Ensayo de la copia real, sin tocar la base activa

El workflow `Restaurar respaldo real (solo aislado)` descarga el artefacto cifrado
de la ejecución de respaldo indicada (por defecto `39073667621`). Comprueba proyecto,
nombre de archivo y SHA-256 de la copia cifrada y del archivo descifrado.

Usa únicamente la contraseña de cifrado del respaldo. El paso de restauración
rechaza recibir `SUPABASE_TEST_DB_URL`: no tiene una conexión al servidor activo.
La consulta agregada de Storage es un paso separado de solo lectura.

La imagen de Supabase se arranca en un contenedor desechable con `--network none`;
se comprueba ese aislamiento antes de restaurar. Los roles que falten se crean
localmente sin login, y se verifica que el restaurador tenga privilegios de
administración en ese contenedor. Se crea una base `restored_backup` vacía y se
ejecuta pg_restore con parada ante el primer error. No se desactiva la validación
de errores para dar el ensayo por aprobado.

Después se consultan solo conteos agregados de la copia restaurada. Si restaura,
se ensayan los 23 candidatos de integración con ROLLBACK en esa copia. Esto no
ejecuta migraciones en Supabase ni incluye 13Y/13X o una nueva APK.

Solo se publican informes JSON de resultado y conteos. No se publican datos
descifrados, SQL privado, contraseñas o errores que pudieran incluir datos.
Al terminar se eliminan el contenedor con sus volúmenes y el archivo temporal
descifrado. Los propietarios originales/roles globales y configuración del
servicio no se reproducen como identidades operativas; `service_recovery_verified`
permanece false aunque la restauración del archivo pase.

## Storage

La inspección de solo lectura del 17 de octubre en la ejecución `39076625021`
encontró **3 buckets y 0 objetos** (0 bytes conocidos, 0 tamaños desconocidos).
Por lo tanto no había binarios de fotos/PDF que copiar en ese momento. Esto no
crea un respaldo automático de futuros archivos y no convierte el dump de la
base en un respaldo de binarios. Volver a inspeccionar antes de las migraciones.

## Ajustes del entorno de ensayo

- El PostgreSQL local no pudo descargar/desplegar todas las capas de la imagen
  por el límite de disco del almacenamiento Docker vfs. No se leyó el respaldo
  real en ese entorno. El ensayo se trasladó a un runner efímero de GitHub.
- El inventario de Storage acepta enteros decimales exactos devueltos por la API
  como cadenas; no convierte tamaños a float ni acepta valores negativos.
- Se preservó el directorio de configuración `/etc/postgresql` de la imagen y
  se usa un administrador verificado dentro del contenedor. La primera prueba
  de restauración se detuvo por permisos insuficientes del rol local, no por
  corrupción del respaldo ni por modificación de la base activa.

## Resultado acreditado

[Ejecución 39077111210](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39077111210)
aprobada el 17 de octubre de 2026 a las 22:57 UTC, commit `73adf88`.

- Descifrado y hashes de la copia real aprobados.
- `pg_restore --exit-on-error` terminó correctamente en la base aislada, con un
  administrador local verificado y red desactivada. Se requirió un rol gestionado
  adicional sin login para las referencias de ACL del archivo.
- Se recuperaron 125 tablas de aplicación. La copia contenía 0 pacientes,
  0 tutores, 0 registros de medicación y 0 metadatos de objetos Storage en las
  tablas consultadas. Este ensayo no acredita migración de registros clínicos
  reales poblados; las pruebas sintéticas con datos conocidos son evidencia distinta.
- Consultas de comprobación aprobadas y ensayo de 23 candidatos aprobado con
  ROLLBACK. `archive_restore_succeeded=true` y `migration_rehearsal_passed=true`.
- Storage remoto volvió a reportar 3 buckets y 0 objetos. No se creó una copia
  de binarios inexistentes y no se supone respaldo de archivos futuros.
- `service_recovery_verified=false`: propietarios/roles operativos, sesiones,
  secretos, configuración de plataforma y pruebas HTTP entre clínicas no quedan
  certificados por este ensayo de archivo.

Las 64 pruebas Python administrativas pasaron también. No se aplicaron candidatos
al servidor real, no se habilitaron admisiones ni se generó APK.
