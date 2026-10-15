# A1 — instalador beta directo, sin Play Store

15 de octubre de 2026. Configuración preparada; no se creó una llave real de la usuaria ni se generó un APK de esta nueva identidad. No aplicar migraciones ni activar la beta por este cambio.

## Identidad y actualización

- ID reservado producción: io.github.alexcore123r.vetdosis; única variante Android actual: beta, ID io.github.alexcore123r.vetdosis.beta, etiqueta VetDosis Pro Beta.
- MainActivity y namespace coinciden. La instalación anterior com.example.vetdosis_pro permanece como otra app. No desinstalarla: no se transfiere automáticamente su caché, preferencias o borradores. Los datos ya guardados en el servidor se consultan iniciando sesión con la misma cuenta y espacio autorizado.
- APP_CHANNEL=beta comprueba en arranque (también release) que SUPABASE_URL sea exactamente el proyecto de pruebas aprobado. CI fija esa configuración; no se conecta al proyecto anterior.
- Enlaces de correo beta: io.github.alexcore123r.vetdosis.beta://login-callback/. Añadir esta URL a Authentication → URL Configuration → Redirect URLs del proyecto de pruebas. No quitar aún com.vetdosis.pro://login-callback/ de la versión antigua. Google permanece desactivado.
- Android allowBackup=false y exclusiones en fullBackupContent/dataExtractionRules para nube y transferencia de dispositivo. Solicitan excluir archivos, bases, preferencias y almacenamiento de dispositivo; validar comportamiento del fabricante en teléfono real. No eliminan respaldos históricos ya existentes ni sustituyen los respaldos explícitos autorizados de la app.

## Firma estable

Release beta exige firma propia. No hay fallback a debug ni publicación de APK sin verificar. No se configuró Play App Signing; queda para Play Store. La llave beta directa no se presenta como llave de Play ni se debe reemplazar por la de carga sin analizar continuidad.

Secretos GitHub Actions requeridos:

- ANDROID_BETA_KEYSTORE_BASE64
- ANDROID_BETA_STORE_PASSWORD
- ANDROID_BETA_KEY_ALIAS
- ANDROID_BETA_KEY_PASSWORD

Variable pública requerida: ANDROID_BETA_CERT_SHA256 (huella del certificado). No es una clave privada. Se compara con ambos APK antes de publicar. GitHub Actions no permite recuperar secretos para descargarlos: por eso es necesaria la copia cifrada independiente.

La conexión de GitHub usada por el asistente devuelve HTTP 403 al administrar secretos. No se intentó sortear esa restricción ni se generó una llave real sin canal de entrega.

## Preparar una sola vez en terminal privada

Puede usarse un ordenador propio o un Codespace privado del repositorio, desde navegador. Confirmar que nadie más accede al terminal o al espacio. Nunca ejecutar en una sesión compartida ni enviar fotos de los archivos de secretos.

1. Obtener main actualizado y ejecutar desde la raíz:

```sh
python3 scripts/android/create_signing.py
```

Requiere Python 3, keytool y gpg. El asistente pide una contraseña de recuperación sin mostrarla; guardarla en un gestor de contraseñas fuera del chat. Si la carpeta .signing contiene archivos, se detiene para no reemplazar una identidad. No borrar esa carpeta para repetir la creación sin revisar primero si ya existe una firma válida.

2. Se crea .signing/vetdosis-beta.signing-backup.gpg, que contiene el keystore y sus contraseñas aleatorias. El asistente verifica que se descifra correctamente antes de informar éxito. Descargar una copia cifrada a un lugar privado fuera del repositorio/Codespace; mantener la contraseña por separado. Sin contraseña no hay recuperación. No adjuntar la copia ni contraseñas al chat.

3. En https://github.com/Alexcore123R/Vet-dosis-pruebas/settings/secrets/actions crear los cuatro secretos, copiando cada valor desde su archivo .signing/ANDROID_BETA_....txt. Se copian directamente al servicio, sin pasar por chat. En Settings → Secrets and variables → Actions → Variables crear ANDROID_BETA_CERT_SHA256 con el contenido del archivo del mismo nombre. No sobrescribir una firma previamente configurada: recuperar su copia en vez de generar otra.

Alternativa de terminal, solo con sesión GitHub de la propietaria que tenga permiso para esos secretos:

```sh
for signing_name in ANDROID_BETA_KEYSTORE_BASE64 ANDROID_BETA_STORE_PASSWORD ANDROID_BETA_KEY_ALIAS ANDROID_BETA_KEY_PASSWORD; do
  gh secret set "$signing_name" --repo Alexcore123R/Vet-dosis-pruebas < ".signing/$signing_name.txt"
done
gh variable set ANDROID_BETA_CERT_SHA256 --repo Alexcore123R/Vet-dosis-pruebas < .signing/ANDROID_BETA_CERT_SHA256.txt
```

No usar --body con un secreto literal ni pegar su valor en el terminal, historial o chat. Si el comando no tiene permiso, usar la pantalla de Settings con la cuenta propietaria. No crear tokens de acceso para enviarlos al asistente.

4. Solo después de guardar copia cifrada y comprobar secretos, lanzar Compilar APK de pruebas. No hace falta activar Google. CI falla al comienzo si falta la firma; es deliberado. Los .txt en .signing contienen secretos sin cifrar: retirarlos del entorno de trabajo una vez confirmado su almacenamiento en GitHub y la copia cifrada externa. .gitignore los excluye, pero eso no los cifra.

## Versiones y verificación

versionCode de CI = segundos UTC desde 2020-01-01, época fija. La cola de compilación es única y las ejecuciones posteriores usan un código mayor; reejecutar un build asigna un código nuevo. No depende de renombrar el workflow ni de resetear run_number. Depende del reloj del runner: si fuera incorrecto, detener publicación y corregirlo, no reducir códigos. El helper rechaza valores fuera del rango de Android. No pasar un build-number antiguo manualmente para distribuir una actualización.

El flag force-version-code-ignoring-abi evita los desplazamientos automáticos por ABI de Flutter: ambos APK llevan el mismo versionCode, comprobado antes de publicar. Están dirigidos a arm32/arm64; no se instalan los dos a la vez.

Verificador de APK: apksigner comprueba firma, certificado esperado, aapt comprueba ID/versionCode/actividad y allowBackup=false. Solo entonces se publican APKs, SHA256SUMS.txt con nombres relativos y BUILD-INFO.json (sin secretos). La clave temporal del runner se elimina incluso si falla el trabajo. No se suben keystore, contraseñas ni copias de recuperación al artefacto de APKs.

## Validación ejecutada y pendiente

- Seis pruebas Python: contador, ausencia de secretos, permisos de archivo, no filtración en stdout, XML, verificación de APK (salidas simuladas de herramientas) y copia cifrada real de una llave ficticia temporal, rechazo de contraseña incorrecta y prevención de reemplazo accidental. La llave ficticia no se distribuye ni configura en GitHub.
- Ocho pruebas Flutter de canal/backend/callback y autenticación; análisis estático limpio.
- YAML del workflow analizado correctamente. No equivale a ejecutarlo en GitHub.
- No hay Android SDK en este workspace: Gradle/recursos y firma efectiva deben comprobarse en Actions tras configurar secretos. No se afirma compilación Android aprobada de A1.
- Pendiente crear firma real, descargar copia cifrada, configurar secretos y URL de redirección, ejecutar build y validar ambos APK con herramientas reales.
- En teléfono: instalar beta junto a anterior, identificar etiqueta/ID, comprobar cuenta/proyecto, abrir enlace real de correo y generar una segunda versión para probar actualización con misma firma y conservación de datos. No desinstalar para resolver una firma incompatible.
- Firma estable no implementa todavía admisiones beta, caducidad de build en servidor ni nuevos permisos. Esas fases siguen separadas.

## Corrección del verificador — 15 de octubre

El primer build firmado generó ambos APK, pero no los publicó al fallar la verificación del certificado. La comprobación aislada 38681456086 confirmó que el certificado real del keystore coincide exactamente con la huella pública configurada. No se cambiaron secretos ni se generó otra llave.

Se reprodujo una incompatibilidad del parser con herramientas Android 37: la etiqueta pasó de `Signer #1 certificate SHA-256 digest` a `V3.0 Signer: certificate SHA-256 digest`. El parser ahora lee únicamente hashes completos del certificado (excluye la huella distinta de la clave pública) y exige que todos los certificados encontrados coincidan con el esperado. Se excluyen versiones RC/preview al escoger herramientas. Las herramientas oficiales 36 y 37 se probaron localmente con firmas reales de un ZIP sintético temporal no instalable, sin usar la llave de la usuaria. No se dispone todavía del SDK completo para compilar Android localmente.

Además, se endureció la creación/comprobación de huellas exportando el certificado a archivo DER antes de calcular SHA-256, para evitar contaminación por mensajes de JVM en stdout. Es una prevención adicional: la comprobación aislada confirmó que la huella existente de la usuaria ya era correcta. Se añadió una comprobación temprana del keystore en CI antes de compilar; el verificador final permanece obligatorio.
