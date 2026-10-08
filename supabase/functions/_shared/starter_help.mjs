export const helpTopics = {
  getting_started:
    "Cómo comenzar con mi espacio personal o clínica y la guía de primeros pasos.",
  permissions: "Cómo funcionan roles, invitaciones y permisos profesionales.",
  payments:
    "Cómo distinguir mi suscripción de los cobros a clientes y cerrar caja.",
  notifications: "Cómo activar avisos de hospitalización y qué límites tienen.",
  report_problem: "Cómo reportar un problema y comunicarme con soporte humano.",
  privacy:
    "Cómo elegir privacidad y contexto de los chats y proteger mis datos.",
};
const facts =
  `VetDosis Pro está en fase de pruebas. El menú abre Inicio guiado, Ajustes, Planes, Ayuda y soporte, Asistente IA, Inventario y los módulos que permite el rol. En Mi cuenta se puede crear un espacio personal o administrar la clínica según permisos. El rol viene del servidor; pagar no autoriza actos profesionales. Las recetas controladas y reportes reservados requieren MVZ responsable habilitado. Planes muestra precios propuestos y pagos de VetDosis; los cobros siguen desactivados hasta configurar servicios reales. Inventario contiene ventas, pagos manuales y cierre de caja de clientes; no necesita conectar una pasarela. En Hospitalización se activan avisos con permisos del dispositivo; en web hay avisos con la hoja abierta, los teléfonos requieren pruebas de app cerrada, batería y Focus. Los chats son privados y excluidos del contexto de otros chats por defecto; compartir y usar contexto son opciones independientes, limitadas por clínica y rol. Ayuda y soporte permite reportes privados con autorización, cinco archivos JPEG/PNG/PDF/TXT de hasta 5 MiB por reporte, mensajes y actualización manual; humanos y contactos requieren configuración real, sin prometer tiempo de respuesta. Las referencias clínicas requieren fuentes verificadas y no deben inventarse. No hay automatización activa de WhatsApp, Drive ni OCR. Esta ayuda incluida usa solo un tema predefinido: no envía texto personal, expedientes, otros chats ni archivos al proveedor.`;
export function helpMessages(topic) {
  if (!Object.hasOwn(helpTopics, topic)) throw new Error("invalid_help_topic");
  return [{
    role: "system",
    content:
      `Eres ayuda de uso de VetDosis Pro en español. Usa exclusivamente estos hechos. Responde con pasos breves y ofrece soporte humano si falta algo. No hagas recomendaciones clínicas, no solicites datos personales o claves, no afirmes configurar, cobrar, resolver ni enviar nada. No inventes botones ni funciones. La respuesta es orientativa y requiere revisión.\n${facts}`,
  }, { role: "user", content: helpTopics[topic] }];
}
export function starterRuntime(env) {
  const provider = env("STARTER_AI_PROVIDER") || "google";
  const model = env("STARTER_AI_MODEL") ||
    (provider === "google" ? "gemini-2.5-flash" : "glm-4.5-flash");
  const allowed = {
    google: ["gemini-2.5-flash", "gemini-2.5-flash-lite"],
    zai: ["glm-4.5-flash", "glm-4.7-flash"],
  };
  const key = env("STARTER_AI_API_KEY");
  if (
    env("STARTER_AI_FREE_TIER_REVIEWED") !== "true" || !key ||
    !allowed[provider]?.includes(model)
  ) return null;
  return { provider, model, key };
}
export function limitedHelpRequest(request, provider) {
  if (provider === "google") {
    request.body.generationConfig = {
      maxOutputTokens: 1024,
      thinkingConfig: { thinkingBudget: 0 },
    };
  } else {
    request.body.max_tokens = 1024;
    request.body.thinking = { type: "disabled" };
  }
  return request;
}
