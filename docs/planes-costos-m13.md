# Propuesta de planes VetDosis Pro

Estado: propuesta de lanzamiento, no lista de precios publicada ni cobros activados.

| Plan | Mensual MXN | Anual MXN | Alcance |
|---|---:|---:|---|
| Gratis | 0 | 0 | Espacio personal y funciones limitadas |
| Individual | 199 | 1,990 | Médico independiente, POS manual y expediente propio |
| Clínica | 799 | 7,990 | Una clínica y todos sus integrantes |
| Beta/regalo | 0 | 0 | Beneficios temporales asignados por administrador global |

El anual equivale a diez mensualidades. Los precios, impuestos, límites, facturación fiscal y comisiones de cobro se revisarán antes de publicar. No incluyen consumo de proveedores de IA con API key propia.

## Límites iniciales propuestos

| Plan | Pacientes | Presupuesto de almacenamiento | Intentos IA/día UTC | Equipo |
|---|---:|---:|---:|---|
| Gratis | 50 | 250 MiB | 5 | Personal |
| Individual | 5,000 | 2 GiB | 200 | Personal |
| Clínica | 50,000 | 10 GiB | 1,000 compartidos | Todos los integrantes |

El espacio individual permite expediente propio, recetas según habilitación profesional, agenda, inventario, ventas y registro manual de efectivo, transferencia y tarjeta, con cierre de caja. No exige conectar Stripe ni compartir datos con la clínica donde trabaja el usuario. No incluye equipo compartido, checado ni acceso a información de otra clínica. Pagar nunca concede un rol clínico o autorización profesional.

El almacenamiento es un presupuesto conservador: datos estructurados, representación de PDF y reserva de 4 MiB por foto de inventario. No equivale exactamente al tamaño físico facturado por Supabase. Al vencer un beneficio se aplica Gratis; los datos existentes no se borran y se bloquean incrementos que excedan los límites. Los intentos de IA se cuentan aunque falle el proveedor; borrar chats no reinicia la cuota.

## Presupuesto orientativo

Estos son supuestos de planificación, no cotizaciones de proveedores: servidor 500 MXN/mes, web/dominio 80, monitoreo/respaldo 100 y reserva 300: **980 MXN/mes**. No incluyen trabajo, soporte, crecimiento, consumo de IA ni comisiones de tiendas.

Si los precios propuestos incluyen IVA de 16% y se supone una comisión de cobro de 4% + 3 MXN por transacción, el ingreso antes de otros costos sería aproximadamente 160.59 MXN por mensualidad individual y 653.83 por mensualidad clínica. El anual dejaría 1,632.92 y 6,565.33 MXN respectivamente. Son estimaciones; impuestos, CFDI y tarifas reales requieren revisión antes de publicar.

## Beta, regalos y recompensas

Beneficios temporales se asignan únicamente desde servidor por el operador global, con referencia y vencimiento. Las clínicas existentes reciben una transición de 90 días al instalar la adaptación; no se registra como pago. La propuesta de lealtad es 1,000 puntos por 30 días: permanece desactivada y los puntos no se generan automáticamente. El canje con una suscripción pagada activa queda bloqueado hasta implementar descuentos en el proveedor. Un regalo vigente retrasa el primer ciclo de cobro; quedan pendientes los casos cercanos a su vencimiento.

## Implementación y activación

Hay catálogo configurable, solicitudes de interés, beneficios temporales, límites de servidor, espacio personal y base de checkout Stripe mensual/anual en MXN. Una solicitud o el regreso del navegador nunca activa el plan: requiere una factura pagada y webhook firmado, verificado e idempotente. Esto cobra la suscripción de VetDosis, no las ventas de una clínica. PayPal y otros proveedores requieren adaptadores futuros.

**Los precios no están publicados y los cobros siguen apagados.** Antes de habilitarlos faltan instalación real, credenciales de servidor, pruebas de sandbox, cancelación/portal, devoluciones, prorrateo, impagos, términos y revisión fiscal. No se han realizado cargos ni conectado cuentas.

Orden después de las adaptaciones existentes: `existing_subscriptions_m13.sql`, `existing_ai_m12.sql`, `existing_plan_files_m13.sql` (requiere fotos M8) y `existing_ai_plan_export.sql`. Son adaptaciones aditivas locales; deben revisarse e instalarse en Supabase al final. La nueva consulta de membresías de la app necesita M13 instalado.

Ver [IA y privacidad](m12-ia-contexto.md) y [pendientes finales](pendientes-revision-final.md).

La revisión añade ayuda IA inicial incluida de temas públicos (sin asesoría clínica ni contenido personal), con cupo separado de cinco intentos por usuario y cien globales/día UTC. Gemini/GLM usan una cuenta del operador revisada antes de activar; su disponibilidad gratuita no se promete ilimitada. El chat con clave propia conserva sus cuotas de plan y condiciones del proveedor. [Detalles](ia-incluida.md).
