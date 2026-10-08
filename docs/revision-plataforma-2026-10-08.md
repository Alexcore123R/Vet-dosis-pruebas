# Revisión de VetDosis Pro — 8 de octubre de 2026

## Resultado y alcance

La estructura modular permite continuar, pero la app todavía necesita una fase de preparación y pruebas integradas antes de operar con datos clínicos o cobrar. Tener pantallas y pruebas locales no equivale a tener servicios instalados, referencias clínicas verificadas o comportamiento confirmado en teléfonos.

Revisé navegación y visibilidad por rol, ramas, inicio, ajustes, acceso, pacientes, cálculos, formatos, recetas, hospitalización, inventario/caja, operación, asistencia, exportación, IA, planes y soporte. Consulté el código de UI/repositorios, configuración móvil/web, adaptaciones y pruebas relevantes. Inspeccioné vistas locales en Chromium en 390×844 y 1440×1000, claro/oscuro, con repositorios sintéticos sin conexión a Supabase. Añadí pruebas a 320 px con texto ampliado 1.6× y medición de contraste de colores principales en las diez combinaciones de temas. Esto no certifica accesibilidad completa ni sustituye probar Android/iPhone.

Las capturas y el registro están en `review/plataforma-2026-10-08/`. `tools/review_preview.dart` es un objetivo exclusivo de revisión con datos ficticios; producción sigue usando `lib/main.dart`. No se han cargado expedientes, claves de proveedor, cuentas ni pagos reales.

## Problemas comprobados y corregidos

| Hallazgo | Cambio realizado |
|---|---|
| Inicio marcaba receta/escáner como pendientes pese a existir partes implementadas | Etiquetas actualizadas; accesos ya implementados dicen Abrir |
| Escáner rápido no tenía ruta funcional | Cámara o código manual y búsqueda en inventario, sin afirmar que verifica dosis o hace OCR |
| Faltaban cálculo rápido y hospitalización en el menú | Añadidos al menú y filtrados según rol; autorizaciones siguen en servidor |
| Se ofrecían módulos reservados a quienes luego recibían denegación | Menú, inicio y ajustes ahora usan una política común de visibilidad; el plan no cambia el rol |
| Las ramas tenían escasa utilidad en el inicio | Accesos por rama y herramienta inicial apropiada: fluidos, metabolismo o agua; nunca seleccionan automáticamente especie o dosis |
| La clínica activa solo se veía después de desplazarse | Se muestra el espacio activo en cabecera para reducir confusión entre clínicas |
| Acciones rápidas ocupaban una sola columna en celulares habituales | Dos columnas donde caben, una con texto ampliado; invitación a la guía después de accesos clínicos |
| Ajustes se limitaban casi a apariencia | Enlaces a cuenta, perfil/firma, formatos/logo, avisos, IA/privacidad, pagos, inventario y respaldo según rol |
| Volver desde un apartado podía salir de la app | El evento de volver de la app retorna a Inicio; rutas web/deep links completos siguen pendientes |
| Títulos largos de chats/modelos podían desbordar | Desplegables expandidos con texto limitado; prueba de teléfono con fuente ampliada |
| La UI mostraba `private`, `none`, `clinic` y nombres técnicos del proveedor | Etiquetas comprensibles en español |
| Casilla obligatoria genérica aceptaba false | Ahora debe estar confirmada antes de enviar |
| Un callback de formulario podía eliminar campos del borrador después de fallar | Se entrega una copia profunda al submit, conservando los datos para reintentos |
| Soporte generaba una operación nueva en cada reintento de un mensaje | Conserva la operación hasta éxito o edición; bloquea editar mientras envía |
| Errores de cuota de pacientes/almacenamiento no indicaban qué hacer | Mensajes hacia Planes sin exponer códigos de base de datos |
| Guardar ajustes no comprobaba el resultado de preferencias | Detecta fallo y lo muestra |
| Pagos no comprobaba si logró abrir el navegador | Comprueba apertura y muestra error; recibos se mantienen exclusivos de admin |
| Almacenamiento aparecía como números grandes de bytes | Cantidades legibles MiB/GiB; presupuesto estimado, sin prometer tamaño físico exacto |
| Web conservaba título/descripción genéricos de Flutter | Nombre, idioma y metadatos de VetDosis |
| Permiso iOS de ubicación aparecía repetido dentro de diccionarios ajenos | Se conserva una sola declaración en la raíz y se valida el plist |
| La ayuda de IA requería clave propia incluso para iniciar | Nuevo canal incluido de temas públicos con Gemini inicial y GLM alternativo, secreto de servidor, límites y activación controlada |

## IA incluida: decisión y límites

La ayuda inicial no necesita una API key del usuario. El proveedor predeterminado preparado es **Gemini**, modelo `gemini-2.5-flash`; también se puede configurar Z.AI con `glm-4.5-flash` o `glm-4.7-flash`. Z.AI se añadió además como proveedor de clave propia para esos dos modelos documentados. Su catálogo público no prueba que una cuenta tenga disponibilidad.

Las páginas oficiales consultadas muestran cuotas gratuitas en Gemini y precios Free en los modelos Flash de Z.AI. Eso no implica capacidad ilimitada, permanencia del precio ni que una clave cualquiera opere sin cobros. Antes de activar se revisan el proyecto/cuenta, cuota efectiva, facturación, región, términos y tratamiento de datos. No se ha hecho una llamada real para validar la cuenta.

Google indica que en servicios gratuitos usa contenido para mejorar productos y prohíbe enviar información sensible, confidencial o personal. Por eso la ayuda incluida tiene **seis temas cerrados de uso de la app**: primeros pasos, permisos, pagos/caja, avisos, reportar un problema y privacidad. El servidor genera el texto a partir de una guía pública. No acepta texto libre, adjuntos, expedientes, otros chats ni nombres/IDs de usuario o clínica para el prompt. La selección de tema y guía pública son lo único enviado al modelo. El chat veterinario con proveedor propio es un flujo independiente que también exige revisar los términos aplicables.

La respuesta orientativa se conserva en un chat privado, excluido del contexto de otras conversaciones por defecto. Límites iniciales: **5 intentos por usuario/día UTC y 100 globales/día**, configurables en servidor dentro de topes. Borrar conversaciones o cambiar de clínica no reinicia la cuota del usuario. Respuesta limitada a 1,024 tokens; sin herramientas externas ni pensamiento solicitado. Reintentos idempotentes; al fallar o agotarse cuota no hay sustitución automática por un modelo de pago.

**Preparada, todavía sin activar:** faltan la clave del operador, revisión efectiva de la cuenta gratuita y despliegue. Ver [configuración y fuentes](ia-incluida.md).

## Lo que falta antes de usar datos reales

| Prioridad | Pendiente | Criterio de cierre |
|---|---|---|
| P0 — uso clínico | Catálogos de dosis/concentraciones, protocolos, contraindicaciones, retiros y clasificación regulatoria continúan vacíos o sin verificar | Fuentes, revisión MVZ, versionado y casos conocidos por presentación; nunca rellenar desde respuestas de IA |
| P0 — instalación | Adaptaciones/Storage/Edge Functions nuevas no están instaladas en Supabase remoto | Revisar esquema actual y respaldo, aplicar orden probado una vez, verificar RLS con cuentas distintas y restauración |
| P0 — cobros | Cancelación, devoluciones, impagos, términos/fiscal y contratos reales de webhooks siguen incompletos | Ensayo sandbox del ciclo completo; conservar catálogo no publicado y checkout desactivado hasta cerrar |
| P1 — acceso | Recuperar contraseña, confirmar/cambiar correo, reautenticación, eliminación de cuenta y gestión integral de miembros/invitaciones | Flujos seguros de token/confirmación, revocación y último admin; no borrar registros firmados/contables por eliminar acceso |
| P1 — habilitación profesional | Hace falta el proceso operativo para verificar y habilitar MVZ, especialmente en espacios individuales | Identificar verificador, evidencia, vigencia y revocación; una cédula capturada o un pago no habilitan al usuario |
| P1 — dispositivos | Alarmas reales, reinicio/batería/Focus, cámara, ubicación, micrófono, firma, impresión y descargas | Ensayos Android/iPhone y navegador HTTPS; compilar iOS en macOS y Android con SDK/firma |
| P1 — privacidad | Avisos definitivos, consentimientos de datos, conservación, respuesta a incidentes, acceso de operadores y exportaciones sensibles | Textos y procesos revisados, secretos con rotación, equipos configurados y registro de accesos |
| P1 — continuidad | Caché clínica cifrada y sincronización por módulo siguen pendientes; hoy requiere conexión | Probar conflictos, revocación offline y pérdida de conectividad; no prometer uso clínico offline completo |
| P1 — formularios | Avisar al salir con cambios sin guardar y recuperación de borradores en todos los editores | Guardar/descartar/cancelar sin pérdida y sin persistir firmas sensibles indebidamente |
| P1 — medicación/caja | Correcciones después de cierre, devoluciones/anticipos/pagos divididos y receta para múltiples aplicaciones deben probarse como un flujo | Simular varios días, actores, frasco parcial, incidencia, devolución y corte; sin duplicar stock o cobro |
| P1 — respaldo | Exportar no demuestra restaurar; Drive y recuperación integral aún pendientes | Restauración ensayada, cifrado, permisos y política de conservación |
| P1 — publicación | Identificadores de paquete, firma de builds, logos/iconos finales y política de suscripción digital Apple/Google | Validar reglas aplicables a México y modalidad clínica/individual antes de publicar checkout en tiendas |

P0 se refiere a habilitar el uso correspondiente, no a impedir revisar la interfaz local. Un flujo no se debe anunciar como operativo mientras falta su requisito de instalación, fuente o servicio.

## Mejoras útiles después de esos bloqueos

1. **Equipo con nombres visibles:** hoy varios listados/asignaciones usan UUID. Crear perfil de identidad mínimo compartible; separar nombre/cargo de ficha médica y credenciales sensibles.
2. **Agenda ligada a paciente y expediente:** elegir paciente existente, advertir duplicados, abrir expediente desde cita y guardar cancelación/reprogramación con motivo. No bloquear animales con nombres coincidentes.
3. **Cálculo → receta → tratamiento:** transferir un resultado confirmado con versión/fuente, peso y fecha; revisión explícita del MVZ sin capturar medicación dos veces. Nunca autocompletar valores clínicos faltantes.
4. **Búsqueda y paginación:** chats, expedientes, reportes e inventario grandes necesitan búsqueda/páginas y estados vacío/cargando/error consistentes.
5. **Diseño compartido:** reutilizar tarjetas, secciones, botones, campos y espaciado; seguir con neumorfismo sin perder contraste, foco ni accesibilidad. Revisar teclado, lector de pantalla y escalas mayores a 1.6×.
6. **Navegación web:** rutas recuperables, enlaces a paciente/receta autorizados y comportamiento del historial del navegador. Los enlaces no deben incluir datos personales ni permitir saltar permisos.
7. **Zona horaria de clínica y monedas:** mostrar horas de forma consistente y distinguir captura local, servidor UTC y reportes; aclarar importes/impuestos/redondeos con formato MX. Los cortes ya conservan su zona, falta consistencia visual global.
8. **Preferencias y avisos:** configurar recordatorios por tipo, resumen de pendientes y estado de sincronización; no añadir alarmas que el dispositivo no puede garantizar.
9. **Soporte operativo:** horarios, personas responsables, avisos de respuesta, exportación y limpieza de adjuntos, revisión de archivos; no prometer atención inmediata antes de tener equipo.
10. **Carga inicial asistida:** importación revisada de pacientes/productos/servicios y detección de errores antes de guardar, sin contaminar la base farmacológica general.
11. **Administrador global:** consola para plantillas base, habilitaciones profesionales, regalos/créditos y revisión de precios; separado del admin clínico. El panel de soporte ya distingue esa asignación.
12. **Integraciones por etapas:** OCR, transcripción SOAP, IA de pedidos, Drive, SMS y WhatsApp Business con autorización, contratos, consumo y pruebas propios.

## Comprobaciones

- Suite Flutter: **135 pruebas completas aprobadas**; navegación/temas, roles, cálculos exactos, fuentes, formularios, consentimiento, reintentos, IA privada/compartida, planes, soporte y nuevos límites/contraste/texto ampliado.
- SQL aislado `ai_plans`: esquema completo como dependencias; pruebas de IA/planes, soporte/adjuntos, operaciones humanas e IA incluida, con cuotas privadas/globales y sin llamadas externas.
- Node: **11 pruebas aprobadas**; contratos de petición/salida de proveedores, cifrado, checkout/webhook, Z.AI y restricciones de la ayuda incluida.
- Deno: tipos de las cuatro funciones de IA/suscripciones comprobados.
- Web: compilación de producción y previsualización sintética; **24 vistas y 44 capturas**, sin errores JS de página/consola, con capturas en celular/computadora, claro/oscuro y partes inferiores de secciones largas. Android/iOS no se presentan como probados en dispositivos.

Los resultados y límites de las pruebas se comunican al terminar la revisión; las capturas no muestran una clínica real ni una conexión instalada.
