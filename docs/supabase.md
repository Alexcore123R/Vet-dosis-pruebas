# M2: acceso y clínicas (base local)

## Implementado

- Registro/login por correo y flujo OAuth Google con Supabase Flutter.
- Sesión restaurada por SDK; clínicas y roles consultados nuevamente en servidor.
- Creación de clínica: el creador confirmado recibe admin por RPC transaccional.
- Varias clínicas por cuenta, selección entre membresías reales, nunca de identidad/rol.
- Código de invitación aleatorio de 256 bits, almacenamiento SHA-256, ligado a correo
  confirmado, un uso, siete días. Solo admin crea/revoca invitaciones.
- Admin elige el rol de la persona invitada; el usuario invitado no elige su propio rol.
- RLS en clínicas, membresías, invitaciones y auditoría.
- Auditoría de creación, membresías y uso/revocación de invitaciones; cliente no modifica eventos.
- Ante fallo de verificación, se descarta la clínica activa y no se concede acceso.
- Android/iOS incluyen el retorno OAuth; Android tiene permiso de Internet.

## Conexión real: configuración local preparada

1. Ya existe un proyecto del usuario. NO aplicar la migración de instalación inicial.
   La adaptación local está en `supabase/adaptations/existing_clinics_m2.sql`;
   su estado y límites están en `docs/base-existente.md`. El usuario confirmó
   su ejecución en Supabase; no volver a ejecutarla. No ejecutar fixtures/tests en el proyecto real.
   Para una base nueva, usar únicamente la migración inicial y compilar con
   `--dart-define=SUPABASE_EXISTING_SCHEMA=false`.
2. En Authentication, habilitar correo con confirmación y Google con su cliente OAuth.
3. Autorizar el callback que muestra Supabase en Google, y en Supabase autorizar
   las URLs exactas de la app web y `com.vetdosis.pro://login-callback/`.
   Evitar comodines amplios en producción. La URL web final se definirá al alojarla.
4. Compilar con URL y clave publicable del proyecto:

```sh
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://PROYECTO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=CLAVE_PUBLICABLE
```

La clave publicable está diseñada para el cliente. Nunca usar la clave secreta o
`service_role` en Flutter, GitHub, instrucciones de compilación o variables públicas.
La conexión del proyecto del usuario está guardada en `supabase/config.local.json`,
excluido de Git. Se compila con `--dart-define-from-file=supabase/config.local.json`.
Ejemplo sin valores reales: `supabase/config.example.json`. El helper
`scripts/flutter_local.sh run -d chrome` o `scripts/flutter_local.sh build web`
incorpora esa configuración (usar VETDOSIS_FLUTTER_BIN si Flutter no está en PATH).
Sin configuración la aplicación muestra conexión pendiente; no crea usuarios simulados.

Comprobaciones de solo lectura con la clave publicable, sin sesión:

- Auth settings responde HTTP 200: correo habilitado, registro permitido,
  Google deshabilitado. Tras el ajuste del usuario, mailer_autoconfirm=false
  verificado: confirmación de correo activa.
- clinics, clinic_members, clinic_invitations y audit_log responden HTTP 401
  permission denied al rol sin sesión. Solicitudes limit=0, sin filas descargadas.
- Confirm email activo y verificado mediante consulta de solo lectura.
  Pendiente probar registro, recepción del correo, confirmación y acceso con una
  cuenta real del usuario. No se crearon usuarios sintéticos en Supabase.
- Google se oculta en UI mientras SUPABASE_GOOGLE_ENABLED=false. Solo activar
  el flag tras habilitar realmente el proveedor y registrar los callbacks.
- No se han creado cuentas, clínicas ni registros de prueba en el proyecto remoto.

## Validación

Flutter: 21 pruebas, incluyendo offline (ver docs/offline.md), además del núcleo/acceso: siete pruebas originales (núcleo, formulario, rol desconocido, auxiliar sin invitación,
fallo de verificación, respuesta tardía tras logout y ausencia de configuración).
Análisis estático y compilación web. PostgreSQL 17 aislado: migración y comprobaciones
reales de RLS/privilegios, aislamiento de clínicas, correo, reutilización, caducidad,
revocación y permisos de auditoría. Se usa un stub de `auth.uid()` para representar
identidades distintas; no equivale a probar Supabase Auth/PostgREST en producción.

Repetir localmente con Docker:

```sh
bash supabase/tests/run.sh
flutter analyze
flutter test
flutter build web --no-wasm-dry-run
```

## Pendiente dentro de M2

- Probar registro, confirmación, OAuth, membresías y logout contra el proyecto real.
- Gestión de invitaciones existentes en UI (el RPC de revocación ya existe).
- Administración de cambios de rol y bajas con protección del último admin.
- Caché offline multiplataforma y sincronización: particiones por usuario/clínica,
  la caché de acceso y el motor de cola ya están implementados (docs/offline.md).
  Conectar adaptadores de datos por módulo, backend versionado/idempotente,
  revisión de conflictos y política de datos sensibles sigue pendiente.
- Definir RLS específicas de propietarios/fichas del personal al crear esos módulos.
- Validar compilaciones nativas y OAuth en Android/iPhone reales.

GitHub guardará el código y podrá ejecutar verificaciones. GitHub Pages puede alojar
la compilación web estática; Supabase seguirá siendo el servidor de autenticación
y datos. Crear un repositorio remoto o publicar se dejará para el paso acordado.
