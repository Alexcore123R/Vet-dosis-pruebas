# Revisión de Storage y Edge Functions — 2026-10-17

Alcance: inspección de código del repositorio de pruebas. **No acredita despliegue remoto ni aceptación de beta.**

## Evidencia local

- Storage clínico: ejecución [39029205418](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39029205418) aprobada antes de añadir las comprobaciones de revocación para UPDATE y DELETE.
- Commit `e6f0535`: añade comprobación de reintento/upsert con permiso vigente y tras revocación.
- Commit `c25f5ed`: añade comprobación de DELETE después de revocar `patient.write` y `clinical.attach`. **No considerar aprobada esta nueva comprobación hasta observar una ejecución posterior del workflow y sus logs.**
- `13X_storage_media.sql` sigue siendo candidato local, fuera del manifiesto inicial de integración.

## Funciones inspeccionadas

### forms-pdf

- Requiere bearer token y obtiene la identidad desde Auth.
- Consulta snapshots/RPC con el cliente del usuario y usa `service_role` únicamente para registrar el documento.
- Recomprueba revision, hash, estado y acceso beta antes de registrar.
- **Pendiente de probar:** revocación de la autorización profesional/permisos entre snapshot inicial y registro; el RPC de registro debe rechazarla incluso si el cliente ya pasó las verificaciones.
- **Pendiente de probar:** idempotencia, firmas, dos clínicas distintas, lectura del PDF existente tras perder acceso y ausencia de exposición de datos mediante mensajes de error.

### ai-gateway

- Usa credenciales cifradas y no las devuelve al cliente.
- Después de invocar al proveedor, revalida beta antes de completar el mensaje.
- **Pendiente de probar:** pérdida de membresía/permisos tras `ai_claim_server`, además de la beta; la operación `ai_finish_server` debe ser el control final de autorización.
- El listado de modelos devuelve la respuesta externa tras validar la clave; revisar si se requiere revalidación de acceso después de la llamada externa, según el contrato de autorización de `ai_key_get_server`.
- **Pendiente de probar:** reintentos, operación duplicada y límite diario con dos usuarios y dos clínicas.

### starter-ai

- Limita la solicitud a temas fijos para `send` y exige consentimiento explícito.
- Revalida beta después de la respuesta del proveedor.
- **Pendiente de probar:** revocación de acceso a clínica o de configuración entre claim y finish; verificar rechazo dentro de `starter_ai_finish_server`.
- **Pendiente de probar:** límites, duplicados, timeout, cambios de configuración y no filtración de prompts/datos.

## Criterios de cierre

1. Workflow Storage posterior a `c25f5ed` exitoso, con trazas de los nuevos casos.
2. Pruebas negativas remotas por HTTP con dos cuentas, dos clínicas y sesión anónima: acceso, borrado, modificación, rutas inválidas y revocaciones.
3. Revisar SQL y permisos de los RPC `*_register`, `*_claim_server` y `*_finish_server`, especialmente autenticación/propiedad en la transacción del servidor.
4. Pruebas de reintentos durante revocación y de URLs firmadas: la revocación de autorización **no invalida retroactivamente** una URL firmada ya emitida durante su TTL.
5. Ningún despliegue hasta validación coordinada de migraciones, variables y cliente por integración de beta.

Estado: revisión estática inicial completada; verificación runtime y despliegue pendientes.
