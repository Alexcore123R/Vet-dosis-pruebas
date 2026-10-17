# Respaldo operativo del proyecto de pruebas

Este es un respaldo administrativo de la base completa de pruebas, no el respaldo
personal de la app. Puede contener datos de todas las clínicas y datos de Auth;
solo la administradora de plataforma debe tener acceso al archivo y la contraseña.
No se modifica el servidor ni se restaura sobre él al crear esta copia.

## Configuración desde el celular

En [GitHub → secretos de Actions](https://github.com/Alexcore123R/Vet-dosis-pruebas/settings/secrets/actions)
crear estos **Repository secrets**, sin pegarlos en el chat:

1. `SUPABASE_TEST_DB_URL`: URI de PostgreSQL del proyecto
   `wtrelwtztkddfktrfdpb`. En Supabase → Connect, usar **Session pooler**, puerto
   **5432**, base `postgres`, usuario `postgres.wtrelwtztkddfktrfdpb` y la contraseña
   de la base. No usar Transaction pooler (6543). El programa exige TLS con
   validación de certificado/hostname y rechaza URLs de otro proyecto.
2. `SUPABASE_TEST_BACKUP_PASSPHRASE`: contraseña distinta de la de la base, de al
   menos 20 caracteres, sin saltos de línea. Guardarla también en un gestor propio
   fuera de GitHub y del chat. Sin ella no se podrá recuperar el archivo.

La URI tiene que incluir la contraseña real en lugar de `[YOUR-PASSWORD]`; los
caracteres especiales de una contraseña deben estar codificados para una URI.
Si no se conoce la contraseña de la base, revisar las conexiones existentes antes
de restablecerla. No hace falta compartirla con el asistente.

## Ejecución y resultado

El workflow **Respaldar base de pruebas (cifrado)** solo se ejecuta manualmente.
Por defecto `check_only=true`: comprueba presencia/formato de secretos y **no crea
ninguna copia**, aunque Actions salga en verde. Para crearla se usa
`check_only=false` una vez configurados los dos secretos.

`pg_dump` usa una instantánea consistente y una conexión de solo lectura. Su salida
se cifra por streaming con OpenPGP/AES256. No hay contraseñas en argumentos de
procesos ni copias sin cifrar en artefactos o Git. La comprobación descifra en un
archivo temporal sin nombre, verifica SHA-256 completo y ejecuta `pg_restore --list`.
El temporal se cierra antes de publicar el resultado. Los errores de conexión o
cifrado no imprimen stderr privado ni la URI.

El artefacto `vetdosis-encrypted-database-backup` contiene solo un `.dump.gpg` y
`manifest.json`; se conserva **7 días** en GitHub. Descargarlo desde el celular y
guardar una segunda copia privada antes de que venza. El manifiesto identifica
proyecto, fecha, hashes y las comprobaciones efectuadas.

## Alcance y recuperación

Incluye los esquemas/datos/ACLs que exporta `pg_dump`, sin los propietarios
originales. No incluye roles globales, configuración de plataforma, secretos de
Edge/GitHub ni los **archivos binarios de Storage**: estos requieren otra copia.
Los respaldos de base contienen metadatos de Storage, no las fotos/PDF binarios.

Verificar descifrado y lectura del archivo no equivale a probar la restauración
completa del Supabase real. El manifiesto mantiene
`full_database_restore_verified=false`. Antes de migraciones debe ensayarse la
restauración en un destino compatible separado, con roles/extensiones adecuados,
y verificar sus datos/políticas. Nunca restaurar esta copia directamente sobre
la base activa para probarla.

La prueba aislada con datos ficticios sí restaura un archivo cifrado en otra base
y verifica datos con NULL, importe decimal, función SQL, RLS y política. Rechaza
contraseña incorrecta, corrupción y exportación vacía. Esa prueba no acredita
todavía la restauración de la copia real.

## Evidencia del 17 de octubre de 2026

- 55 pruebas Python administrativas aprobadas localmente.
- [Prueba cifrada 39069134852](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39069134852)
  aprobada en GitHub, incluida restauración sintética y rechazos de corrupción/clave incorrecta.
- [Comprobación de configuración 39069134970](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39069134970)
  terminó sin crear respaldo: ambos secretos están ausentes. `backup_created=false`.
  No se ha conectado pg_dump al proyecto real ni se ha generado una copia recuperable de él.

### Primera copia real creada

[Respaldo 39073667621](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39073667621)
completado el 17 de octubre de 2026 a las 22:06 UTC. Se verificaron descifrado
íntegro por SHA-256 y lectura del archivo con pg_restore. El artefacto
`vetdosis-encrypted-database-backup` (ID 12116465184, 1 429 869 bytes) está disponible
hasta el **24 de octubre de 2026, 22:06 UTC**. La administradora debe descargarlo
y conservarlo fuera de la retención temporal de Actions.

Los dos primeros intentos no publicaron copias: el contenedor no confiaba en la
CA de Supabase. Se incorporó la raíz pública oficial de 2021, fijada por SHA-256,
combinada con las raíces del sistema. Se mantuvo `sslmode=verify-full`; no se
desactivó TLS ni la validación del hostname. El test aislado posterior
[39073667133](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39073667133)
pasó también.

Esto sustituye el estado previo de secretos ausentes. La restauración completa
del archivo real en un entorno compatible y la copia de binarios Storage
**siguen pendientes**; no se acredita recuperación integral del servicio todavía.
