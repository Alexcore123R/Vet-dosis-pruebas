# APK beta para revisión del 17 de octubre

Se empaqueta el cliente actual para el proyecto de pruebas
`wtrelwtztkddfktrfdpb`, con identificador
`io.github.alexcore123r.vetdosis.beta`. Se conserva la firma propia y se incrementa
versionCode. No se activa Google sin verificar su configuración.

La generación exige análisis Flutter, batería completa de pruebas, comprobación
de keystore y verificación de firma/identificador/versionCode/allowBackup de ambos
APK. El artefacto incluye arm64-v8a, armeabi-v7a, SHA256SUMS y BUILD-INFO.

Se corrigieron dos adaptadores de revisión/prueba desactualizados: TeamFake
declara su permiso de administración de forma explícita, y el AiFake de la vista
de revisión implementa rotateKey. No se cambiaron permisos de producción para
hacer pasar el análisis.

## Paquete generado

[Compilación 39078100253](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39078100253)
aprobada sobre `ac7c2b1`: análisis completo y **363 pruebas Flutter** aprobados.
VersionCode **214441940**, Google desactivado. APK ARM64 de 32.5 MB y ARM32 de
29.2 MB; ambos con firma, package/versionCode y allowBackup=false verificados.

[Descarga del artefacto](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39078100253/artifacts/12117727505):
`vetdosis-pruebas-apks`, 31 268 291 bytes comprimidos; retención hasta el
**31 de octubre de 2026, 23:23 UTC**. El ZIP debe extraerse antes de instalar el
APK correspondiente. La variante habitual ARM64 es
`app-arm64-v8a-beta-release.apk`; la ARM32 es `app-armeabi-v7a-beta-release.apk`.

La publicación de este build se registró correctamente por el servidor con
caducidad de 90 días, sin renovar builds anteriores. Se eliminó el keystore
temporal del runner.

## Límite de esta entrega

Generar el APK no aplica el esquema de integración al servidor. La inspección
remota y el ensayo de recuperación acreditan una base previa al corte de permisos:
`app_module_workspace` y otras RPC de los candidatos aún no se desplegaron.
[Inspección 39078559378](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39078559378)
lo confirmó nuevamente durante la compilación: contrato de módulos ausente y
`deploy_ready=false`.
La interfaz nueva conserva el bloqueo de módulos ante contrato ausente; por ello
pacientes, agenda, inventario y otros módulos revisados pueden quedar ocultos
hasta aplicar el esquema compatible y conceder permisos explícitos.

La renovación de claves también requiere 13Y y el gateway compatible. No se
ofrece esta entrega como beta clínica operativa ni como prueba HTTP entre clínicas.
No se rebajan los controles del cliente para simular compatibilidad.

El workflow registra únicamente la publicación del build verificado y su
caducidad en el servidor; esto no abre admisiones ni instala migraciones clínicas.
La prueba en teléfono real sigue siendo necesaria tras descargar el paquete.

## APK corregido disponible — 18 octubre

La interrupción del entorno se resolvió. La compilación
[39082429107](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39082429107)
terminó correctamente sobre `3b63292` (incluye la corrección `0859ff8` de recarga
del dashboard al recibir/revocar permisos en la misma sesión).

- Análisis Flutter sin incidencias y **365 pruebas aprobadas**.
- VersionCode **214446065**, firma propia y verificaciones de ambos APK aprobadas.
- [Artefacto 12120185046](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39082429107/artifacts/12120185046),
  `vetdosis-pruebas-apks`, 31 271 742 bytes; disponible hasta el **1 noviembre,
  00:36 UTC**. ARM64 32.5 MB y ARM32 29.2 MB. Extraer antes de instalar.
- No hay cambios de código Flutter posteriores en las dos auditorías añadidas
  por GPT-6 (`caa0382`, `b8761a3`); estas son workflows de solo lectura.

El contrato de módulos y 14A/14B ya están instalados, según 39081043942.
La auditoría 39110094504 confirma cuentas separadas, clínica `vet prueba1`,
concesiones clínicas vacías y sin habilitación profesional vigente para la cuenta
clínica indicada por la usuaria. Falta elegir/aplicar el alcance por persona;
instalar este APK no concede permisos. IA 13Y/Edge, pruebas con dos sesiones
reales y comprobación en teléfono continúan pendientes. Admisiones cerradas.
