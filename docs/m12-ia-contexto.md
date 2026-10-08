# M12 — IA, historial y contexto

Implementación local para OpenAI, Google, Anthropic y Z.AI (este último requiere la adaptación de revisión). Cada usuario puede registrar su propia API key y seleccionar modelos consultados al proveedor; el admin puede configurar una conexión para su clínica. La lista está limitada a la primera página de hasta 100 modelos y la compatibilidad real necesita pruebas de cada cuenta. No se ha llamado a un proveedor con claves reales. El consumo se factura aparte por ese proveedor.

## Privacidad y contexto

Los chats comienzan privados y excluidos del contexto de otras conversaciones. Visibilidad y uso en contexto son decisiones independientes: ninguno, personal o de clínica. Para compartir contexto clínico el autor debe compartir el chat y elegir los roles que pueden leerlo. Un admin no puede leer un chat privado ajeno. Todo acceso requiere pertenencia actual a la misma clínica; el plan individual conserva su espacio propio.

Cada envío pide confirmar proveedor/modelo y permite elegir contexto personal y de equipo por separado. El contexto es una selección limitada de conversaciones recientes, no todo el historial. La conversación actual mantiene continuidad aunque esté excluida de otras conversaciones. No se adjuntan automáticamente expedientes ni datos de pacientes. Los fragmentos se marcan como información no verificada y no como instrucciones.

El servidor vuelve a revisar los permisos al guardar la respuesta: si cambió la política de una conversación usada como contexto, descarta esa respuesta. Revocar permisos no retira información ya enviada al proveedor ni borra respuestas previamente generadas. La conservación del proveedor depende de sus términos y configuración.

## Claves y ejecución

Las claves se cifran en servidor con AES-GCM y vínculo al proveedor y propietario/clínica. La app no recibe el secreto guardado. `AI_KEY_ENCRYPTION_SECRET` debe ser base64 de 32 bytes; `SUPABASE_SERVICE_ROLE_KEY` y secretos de Stripe viven exclusivamente en Edge Functions. No hay fallback a texto plano. La rotación de la clave maestra y una consola de operador global siguen pendientes.

`ai-gateway` valida la identidad con Supabase, usa destinos fijos de los proveedores admitidos, limita contexto y salida y reclama cada solicitud una sola vez. Hay cuotas diarias independientes del borrado de chats y recuperación de solicitudes atascadas después de dos minutos. No ejecuta acciones clínicas, emite recetas ni modifica cálculos. Las respuestas se muestran como IA sin verificar; las referencias clínicas y los motores de cálculo conservan sus reglas originales.

## Instalación y pruebas

Después de M13 instalar `existing_ai_m12.sql`, desplegar `ai-gateway` y configurar el secreto de cifrado. `existing_ai_plan_export.sql` añade al respaldo únicamente los chats del usuario que exporta y datos de suscripción, sin claves ni chats privados ajenos.

Pruebas locales: `bash supabase/tests/run.sh ai_plans`, `node --test supabase/tests/ai_billing.test.mjs`, Flutter y comprobación de tipos Deno. Falta probar contratos reales, modelos, revocación concurrente, facturación y comportamiento en dispositivos. OCR, dictado SOAP e IA de pedidos todavía requieren sus integraciones específicas.

La [ayuda IA incluida](ia-incluida.md) es un flujo separado de temas públicos: no usa tus mensajes ni contexto. El catálogo Z.AI es documental y no valida disponibilidad de cuenta. La [revisión de plataforma](revision-plataforma-2026-10-08.md) registra correcciones y pendientes.
