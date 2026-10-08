# IA incluida y Z.AI — configuración de revisión

El servicio inicial es ayuda de uso con temas públicos predefinidos. No es un segundo motor clínico. Está disponible en la pantalla Asistente IA y guarda respuestas en chats propios. Gratis para el usuario, sujeto a disponibilidad y cupo global; no requiere que cada usuario aporte una clave. La cuota de ayuda incluida es independiente de las cuotas de chat con clave propia del plan.

## Fuentes oficiales consultadas el 8 de octubre de 2026

- [Gemini — precios y free tier](https://ai.google.dev/gemini-api/docs/pricing): `gemini-2.5-flash` y Flash Lite tienen cuota gratuita; la página distingue free tier y paid tier.
- [Gemini — términos](https://ai.google.dev/gemini-api/terms): en Unpaid Services se usa contenido para mejorar productos y se indica «Do not submit sensitive, confidential, or personal information to the Unpaid Services». La ayuda incluida no envía datos de usuarios, pacientes ni chats.
- [Z.AI — precios](https://docs.z.ai/guides/overview/pricing): GLM-4.5-Flash y GLM-4.7-Flash aparecen Free. No equivale a todos los modelos GLM ni elimina límites/condiciones de cuenta.
- [Z.AI — chat completions](https://docs.z.ai/api-reference/llm/chat-completion): endpoint fijo y formato compatible de mensajes; se devuelve contenido, sin mostrar razonamiento interno.

Estas páginas pueden cambiar. Revalidar modelo, cuota, condiciones de uso y tratamiento de datos al activar. No se ha comprobado disponibilidad de una cuenta concreta. No se asume que Z.AI permita datos sensibles ni se sustituye revisar sus condiciones por el hecho de que el modelo tenga precio Free.

## Instalación pendiente

1. Después de M12/M13 aplicar una sola vez `supabase/adaptations/existing_starter_ai_review.sql`. Añade límites/solicitudes privadas y amplía el proveedor admitido de claves propias a `zai`.
2. Desplegar `starter-ai`; requiere identidad autenticada y pertenencia actual al espacio, incluso cuando `verify_jwt=false` porque la función valida `auth.getUser`.
3. Configurar **solo en servidor**, nunca en Flutter, estas variables:

| Variable | Valor/alcance |
|---|---|
| `STARTER_AI_API_KEY` | Clave del proyecto/cuenta del operador, no la de un usuario |
| `STARTER_AI_PROVIDER` | `google` por defecto; alternativa `zai` |
| `STARTER_AI_MODEL` | `gemini-2.5-flash` por defecto en Google; `glm-4.5-flash` en Z.AI |
| `STARTER_AI_FREE_TIER_REVIEWED` | `true` solo después de revisar cuenta, facturación, términos y cuota |

4. Desde administración de servidor habilitar `private.starter_ai_config` y hacer coincidir proveedor/modelo con las variables. Sin las dos configuraciones coincidentes permanece no disponible. No se expone un botón de activación al admin clínico.
5. Probar respuestas con temas públicos, errores de cuota y revocación; configurar un procedimiento para suspender servicio y revisar consumo. No activar herramientas, grounding de pago ni fallback automático.

Solo modelos revisados en la allowlist: Google `gemini-2.5-flash`/`gemini-2.5-flash-lite`; Z.AI `glm-4.5-flash`/`glm-4.7-flash`. El operador es responsable de revisar si la cuenta consume cuota gratuita o tiene facturación activa: una bandera en la app no comprueba el estado de la cuenta del proveedor.

## Límites y privacidad

Por defecto cinco intentos por usuario/día UTC, cien en toda la plataforma/día y hasta 1,024 tokens de salida. Los topes configurables son veinte por usuario y mil globales. Las cuotas cuentan intentos, incluidos fallos; borrar chats o cambiar de clínica no las reinicia. Hay idempotencia por usuario/operación, reclamación única del trabajo y expiración de solicitudes atascadas a los dos minutos al revisarlas. Si se desactiva mientras responde, no guarda esa respuesta.

El cliente solo manda un código de tema permitido; no se aceptan prompt, modelo, proveedor, archivos ni contexto libres en el envío. La función obtiene del servidor el tema/modelo y construye la consulta con una guía pública. El proveedor recibe esos textos y la infraestructura normal de una petición del servidor, sin identificadores de clínica/usuario en el prompt. No ejecuta acciones en la cuenta.

La respuesta se guarda en un chat privado, contexto none por defecto. Los clientes no pueden leer ni alterar las tablas privadas de configuración, uso o solicitudes. Al borrar el chat se conservan cuotas/recibos mínimos y se cancela una respuesta pendiente. Las solicitudes privadas todavía no tienen una política automatizada de purga: definir conservación en la revisión final.

Z.AI con API key propia usa AES-GCM igual que los otros proveedores y destinos fijos. Su selector muestra dos modelos del catálogo público documentado, no una verificación de acceso de la cuenta. El usuario mantiene el control sobre contexto y contenido enviados con su clave. Google gratuito no debe recibir datos sensibles aun usando una clave propia.

Pruebas locales: SQL `ai_plans`, Node `ai_billing.test.mjs`, tipos Deno y pruebas Flutter de consentimiento/disponibilidad. No hubo llamadas reales a Gemini o Z.AI ni se instaló esta configuración remotamente.
