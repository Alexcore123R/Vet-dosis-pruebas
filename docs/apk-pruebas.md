# APK de pruebas

Flujo manual de GitHub Actions: `Compilar APK de pruebas`. Destino Supabase fijo: wtrelwtztkddfktrfdpb.

En Settings → Secrets and variables → Actions → Variables crear `SUPABASE_TEST_PUBLISHABLE_KEY` con la clave publicable del proyecto de pruebas. Nunca usar clave secreta/service_role. Esta variable es pública para el cliente y acaba incluida en el APK; las protecciones corresponden a Auth/RLS/RPC.

Ejecutar desde Actions seleccionando la rama que contenga los cambios que se quieren probar; registrar su commit exacto junto con el APK. El flujo obtiene dependencias, analiza, ejecuta pruebas y compila con Flutter 3.47.6 y Java 17. Genera instaladores separados arm64-v8a y armeabi-v7a, con SHA-256, en el artefacto `vetdosis-pruebas-apks` (14 días).

La beta actual usa firma propia persistente, preparada desde los secretos de Actions y comprobada contra su huella configurada antes y después de compilar. Su identificador es `io.github.alexcore123r.vetdosis.beta` y cada compilación incrementa versionCode. Esta configuración sustituye la antigua firma debug descrita en versiones iniciales de esta guía.

Descargar el ZIP del artefacto, extraerlo e instalar arm64 primero; usar armeabi-v7a si el sistema no admite arm64. Instalar como actualización de la beta existente, sin desinstalar ni borrar datos. Solo habilitar instalación desde la aplicación utilizada. Las compilaciones nativas anteriores ya fueron verificadas; cada entrega nueva debe completar sus comprobaciones y después revisarse en el teléfono. Los renders de interfaz no sustituyen esa revisión.

Pruebas en teléfono: acceso con las cuentas beta autorizadas, selección de espacio, búsqueda y registro de un paciente ficticio y aislamiento entre espacios. Generar un APK no abre admisiones beta ni crea cuentas nuevas. La habilitación profesional no se concede por crear clínica/admin. Pruebas de PDF con responsable habilitado requieren el procedimiento privilegiado previsto y revisión del caso. Alarmas: permisos, segundo plano/app cerrada, pantalla apagada, reinicio y ahorro de batería; no atribuir garantía a una alarma hasta medirla en dispositivo.
