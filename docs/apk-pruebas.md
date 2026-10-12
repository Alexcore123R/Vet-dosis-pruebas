# APK de pruebas

Flujo manual de GitHub Actions: `Compilar APK de pruebas`. Destino Supabase fijo: wtrelwtztkddfktrfdpb.

En Settings → Secrets and variables → Actions → Variables crear `SUPABASE_TEST_PUBLISHABLE_KEY` con la clave publicable del proyecto de pruebas. Nunca usar clave secreta/service_role. Esta variable es pública para el cliente y acaba incluida en el APK; las protecciones corresponden a Auth/RLS/RPC.

Ejecutar desde Actions con rama main. El flujo obtiene dependencias, analiza, ejecuta pruebas y compila con Flutter 3.47.6 y Java 17. Genera instaladores separados arm64-v8a y armeabi-v7a, con SHA-256, en el artefacto `vetdosis-pruebas-apks` (14 días).

Es una versión de pruebas firmada con la clave debug del runner. No es firma de publicación. Entre runners puede cambiar la firma y ser necesario desinstalar para actualizar (se pierde almacenamiento local); no capturar datos reales. Resolver firma persistente antes de pruebas que deban conservar caché o distribución estable.

Descargar el ZIP del artefacto, extraerlo e instalar arm64 primero; usar armeabi-v7a si el sistema no admite arm64. Solo habilitar instalación desde la aplicación utilizada. Android 14 de HONOR X6 se probará después de obtener una compilación satisfactoria. La primera compilación nativa aún está pendiente: resolver cualquier error del flujo antes de afirmar compatibilidad.

Pruebas iniciales: registro con dos correos, confirmación, login, una clínica ficticia por cuenta, aislamiento. La habilitación profesional no se concede por crear clínica/admin. Pruebas de PDF con responsable habilitado requieren el procedimiento privilegiado previsto y revisión del caso. Alarmas: permisos, segundo plano/app cerrada, pantalla apagada, reinicio y ahorro de batería; no atribuir garantía a una alarma hasta medirla en dispositivo.
