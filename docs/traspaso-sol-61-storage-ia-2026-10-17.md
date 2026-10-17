# Traspaso a integración beta — Storage, Edge e interfaz IA

Fecha: 2026-10-17. Responsable de integración: Sol 6.1.

## Validación posterior por integración

Actualización tras `675a48e`: se incorporaron la renovación y sus pruebas. El ensayo local de `run_ai_key_rotation.sh` pasó después de aplicar todos los candidatos del paquete inicial de permisos, incluido 13P. Cubre incremento de versión, rechazo de usuario ajeno, bloqueo de acceso RPC directo para `anon`/`authenticated`, descarte de respuesta obsoleta y guardado de respuesta con versión vigente. Los pendientes históricos de abajo sobre ausencia de incremento quedan superados por 13Y; la carrera HTTP real sigue pendiente.

Orden para el cliente nuevo: base IA → paquete de permisos → 13Y → Edge compatible → cliente con renovación. 13Y sigue separado del manifiesto de 23 candidatos: aplicar únicamente ese manifiesto no habilita el botón Renovar del nuevo cliente. No se ejecutó ninguna migración remota ni se compiló APK en esta revisión.

- Incorporado `73b2fd4`: el gateway compara `key_version` tras consultar modelos. El RPC `ai_key_get_server` incluye ese campo mediante `to_jsonb(k)`. Las 11 pruebas Node de proveedores/cifrado/facturación pasan. Estas pruebas no simulan aún la carrera de rotación en el gateway.
- Condición pendiente del issue #1: el esquema da a `key_version` un valor inicial de 1; los caminos actuales de guardado crean una conexión nueva y no muestran renovación del mismo ID ni incremento de versión. La comparación es compatible con el contrato, pero no demuestra protección frente a una actualización de credencial que conserve la versión. Requiere prueba de rotación concurrente y garantía de incremento antes de cerrar ese caso. No se desplegó.

- Cambios integrados hasta `e0c0d0c`. Flutter analyze de `app.dart`, módulo IA y pruebas pasó en [39059203487](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39059203487).
- Pasaron las pruebas de configuración separada, revocación con actualización de lista, chat, planes, revisión de plataforma y navegación. El simulador de planes declara ahora `can_manage` explícitamente; no se modificaron permisos de producción.
- La sección siguiente conserva el estado del traspaso original. La validación automatizada de Flutter queda cubierta por esta ronda; siguen pendientes compilación Android, revisión visual en dispositivo, pruebas remotas y el issue #1 de rotación de credenciales. No hubo despliegue en Supabase ni apertura de beta.

## Confirmado en el repositorio

- Storage clínico 13X: candidato local, **no desplegado** y fuera del paquete esencial de 23 migraciones.
- GitHub Actions Storage: [39029832078](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39029832078) y [39057670193](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39057670193) completados exitosamente, cubriendo pruebas locales de autorización y revocación.
- `ai-gateway`: revalidación de beta y acceso a credencial después de obtener el listado de modelos (commits `df736a5`, `22ef059`).
- Interfaz Flutter: `AiScreen(configurationOnly: true)` presenta alta y revocación de proveedores en una vista separada (commit `9e46caa`). La opción de Ajustes «Proveedor de IA y privacidad» abre esta vista (commit `098e7ff`). El asistente conserva chats, modelos, consentimiento y privacidad de cada conversación.
- La navegación a la configuración exige cuenta, conexión y autorización de la sección; el servidor conserva sus propias comprobaciones. No se modificó el proyecto remoto.

## Validaciones que NO se han acreditado

1. **Flutter analyze, compilación Android y prueba visual** de ambos modos: no están ejecutados. En particular revisar el renderizado y el flujo al revocar claves o regresar de Ajustes.
2. Pruebas HTTP reales en el Supabase de pruebas con cuenta A/ B, dos clínicas y usuario anónimo, incluyendo cancelaciones, expiración y URLs firmadas.
3. Despliegue coordinado de `13X`, Edge Functions y cliente; revisar dependencias, backups y políticas antes de aplicar.
4. Verificar en SQL de servidor las RPC de registro PDF y finalización de IA bajo revocación durante la solicitud.
5. [Issue #1](https://github.com/Alexcore123R/Vet-dosis-pruebas/issues/1): rotación de credenciales durante consulta de modelos. Requiere considerar versión de credencial no secreta; **no resuelto**.

## Propuesta de integración

Sol 6.1 puede continuar su trabajo de integración y planificación, pero **no considerar aprobado el APK ni habilitar beta** hasta análisis/compilación Flutter, validación remota y revisión de dependencias. Evitar reescribir en paralelo `lib/core/app.dart` y `lib/modules/ai/presentation/ai_screen.dart` sin revisar los commits anteriores.

Este documento es el punto de entrega del frente de Storage/Edge/interfaz; no es autorización automática de despliegue.

## Adenda: rotación de credenciales de IA (17 octubre 2026)

La implementación candidata quedó integrada en GitHub y verificada **localmente**, sin desplegar Supabase:

- `supabase/proposed/13Y_ai_key_rotation.sql`: renovación de credenciales con incremento atómico de `key_version`. Un trigger captura la versión al cambiar la solicitud a `processing`; `ai_finish_server` vuelve a comprobar esa versión bajo bloqueo de fila antes de guardar la respuesta.
- `ai-gateway`: acción `rotate_key`; revalidación al devolver modelos y respuestas de `send`.
- Flutter: botón «Renovar» en Ajustes → Proveedores de IA; repositorio y contrato conectados.
- [SQL 39060567086](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39060567086): **aprobado**, incluye rotación autorizada, rechazo de usuario ajeno, captura de versión y rechazo de respuesta obsoleta.
- [Flutter 39060470575](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39060470575): **aprobado**, análisis y pruebas del panel y navegación.
- Ensayo general de integración [39060395397](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39060395397): aprobado, pero no supone que 13Y esté dentro del paquete de 23 candidatos.

**A Sol 6.1:** puede proseguir con la integración. Para el despliegue, incluir 13Y explícitamente tras la base de IA, revisar el orden y el contrato, y realizar pruebas HTTP con cuentas reales de prueba, incluida rotación verdaderamente concurrente mientras un proveedor externo está respondiendo. No se ha ejecutado 13Y remotamente ni generado un APK nuevo con estos cambios. La ejecución local verde no autoriza por sí sola abrir la beta.
