# Traspaso a integración beta — Storage, Edge e interfaz IA

Fecha: 2026-10-17. Responsable de integración: Sol 6.1.

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
