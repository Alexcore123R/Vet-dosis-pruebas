# Google login: proyecto de pruebas

Supabase: wtrelwtztkddfktrfdpb. El flujo actual es OAuth de navegador mediante Supabase, no SDK nativo Google. Por eso se crea cliente OAuth de tipo aplicación web, aunque se pruebe en Android. No requiere configurar SHA del APK para este flujo.

1. Abrir https://console.cloud.google.com/ y crear/seleccionar proyecto para VetDosis pruebas.
2. En Google Auth Platform (o APIs y servicios → Pantalla de consentimiento OAuth), configurar marca/nombre VetDosis Pro Pruebas y correos de soporte/desarrollador. Audiencia externa si no es una organización interna. Mantener estado de prueba y añadir las dos cuentas Google de prueba en usuarios de prueba. No añadir permisos de Drive; login usa identidad básica.
3. En Clientes/Credenciales, crear ID de cliente OAuth de tipo Aplicación web. URI de redireccionamiento autorizado EXACTO:
   https://wtrelwtztkddfktrfdpb.supabase.co/auth/v1/callback
   Comprobarlo también en la pantalla Google de Supabase. No poner aquí el esquema móvil.
4. Guardar Client ID y Client Secret exclusivamente en Supabase → Authentication → Sign In / Providers → Google. Activar proveedor y guardar. No pegar secreto en chat, repositorio ni variables de APK. No cambiar opciones de seguridad como saltar nonce o permitir usuarios sin correo salvo justificación independiente.
5. Supabase → Authentication → URL Configuration → Redirect URLs: añadir exactamente
   com.vetdosis.pro://login-callback/
   Cuando se publique web, añadir su URL exacta. No inventar dominio ni usar comodines generales.
6. Avisar que Google y redirect están guardados. Codex comprobará configuración pública de Auth y ejecutará Compilar APK de pruebas con enable_google=true. El flujo se niega a habilitar el botón si Supabase no anuncia Google habilitado. Esta comprobación no valida el secreto ni toda la configuración Google.
7. Probar con cuentas autorizadas: navegador → selección cuenta → Supabase → app, sesión y membresías del usuario correcto. Confirmar casos de correo ya registrado y cuenta nueva sin dar roles automáticamente. Nunca atribuir habilitación MVZ por login Google.

Antes del lanzamiento se revisan marca, dominio/contacto, aviso de privacidad, URLs web y requisitos de publicación de Google que correspondan. Las pruebas con audiencia restringida pueden preceder dominio propio. No se activa acceso a Drive para respaldos por configurar login Google.

Los APK actuales usan firma debug del runner, que puede cambiar entre ejecuciones. Antes de reemplazar instalación evaluar firma persistente o desinstalación controlada; no prometer actualización que conserve caché hasta resolverlo.
