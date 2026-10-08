# Cobros, pagos y plataformas por clínica

La app ya distingue efectivo, transferencia y tarjeta en las ventas/cortes M8. La adaptación aditiva `existing_payment_references.sql`, posterior a M9–M11, añade transacciones externas de ingreso o egreso y conciliaciones anexas. Ninguna de estas referencias ejecuta un cargo, crea otra venta, mueve caja o descuenta stock. Los gastos reales de caja siguen teniendo su captura M8; enlazar ambas capturas e importar extractos queda pendiente.

Cada clínica puede escribir el nombre del banco, terminal o plataforma que usa; no se exige un banco común. Puede registrar referencias de Stripe, PayPal u otro proveedor, fecha, importe bruto en MXN y últimos cuatro dígitos de tarjeta (opcionales). No hay campos para número completo, CVV, contraseñas o tokens privados; la RPC rechaza campos desconocidos. No copiar esos datos en notas.

El registro queda `pendiente_revision`. Solo admin concilia con motivo, comisión y decisión; neto = bruto − comisión. Se conserva quién reportó y quién revisó con hora del servidor. Corregir una decisión anexa otra, sin borrar historia. La UI muestra las transacciones del usuario o todas si es admin; ninguna clínica consulta otra.

Una referencia puede enlazarse a una venta existente de la misma clínica/cajero y del mismo medio; deben coincidir los importes permitidos. Se bloquean referencias repetidas para un proveedor dentro de la clínica. La suma de referencias verificadas vinculadas no puede superar la venta; los reintentos tienen identidad de operación. Las referencias sin venta siguen siendo datos externos, no ingresos adicionales del corte. Una conciliación manual no equivale a confirmación bancaria automática.

## Conexión futura para cobrar dentro de la app

Debe configurarse por clínica y por proveedor. Stripe y PayPal tendrán adaptadores independientes: sesión/enlace de pago creado por el backend, ID propio, importe y moneda congelados, expiración, estado pendiente y notificaciones verificadas del proveedor. El regreso del navegador o una captura de pantalla no marcarán un pago como confirmado. Eventos duplicados o fuera de orden deben ser idempotentes y comprobar clínica/importe/moneda. Devoluciones, contracargos, comisiones y liquidaciones necesitan eventos separados.

Los secretos se guardarán en servidor; onboarding/cuentas comerciales son de cada clínica. No hay pasarela conectada todavía, ni cargos reales, pruebas con tarjetas, webhook desplegado o elección obligatoria de proveedor. “Cualquier banco” significa que podemos registrar sus referencias manualmente; automatizar cada banco depende de la API o integración disponible. Pagos divididos entre varios medios, anticipos, saldos pendientes y cuentas por cobrar requieren ampliar el modelo de cobro antes de habilitarlos.

El respaldo operacional M11 incluye estas dos tablas. CSV exporta los registros visibles, sin convertirse en un nuevo movimiento financiero.
