# 2B-12: gestión de inventario, caja y referencias de pago

Candidato local **13I2**, posterior a 13I1, 16-oct-2026. Sin despliegue, apertura de beta ni APK. Reutiliza los movimientos, recibos, ventas, lotes, comisiones y cortes existentes; conserva la última versión de venta M9 y el candado clínico 13I1.

## Estado y alcance

- **Implementado y probado:** dispensación 13I1; sus condiciones se vuelven a probar después de este candidato.
- **Preparado local:** este corte SQL/Flutter de catálogo, lotes, ajustes, pedidos, fotos, enlace de frascos, caja, preparación de cargos y referencias externas.
- **Aplicado en remoto y probado:** este candidato no está aplicado a Supabase. GitHub prueba bases aisladas; no equivale a despliegue.
- **Pendiente:** corte transversal de reportes/formatos/respaldos y demás dependencias; Auth/Storage/Edge reales con dos cuentas y clínicas, revisión coordinada y APK compatible.

No se necesita otra decisión clínica/normativa para este bloque. Se separan capacidades operativas ya aprobadas, sin concederlas automáticamente y sin convertir puestos, cédulas capturadas o delegaciones anteriores en autoridad.

## Permisos por persona

Todos requieren además `inventory.read`, pertenencia vigente y una concesión efectiva no vencida. `inventory.read` permite consultar productos, lotes, precios, movimientos y pedidos; no abre caja ni documentos clínicos.

| Permiso | Acción |
|---|---|
| `inventory.manage` | Catálogo/precios, configuración horaria, revisión de inventario histórico, fotos y tarifas de aplicación. |
| `inventory.receive` | Entradas de lote con su movimiento. |
| `inventory.adjust` | Ajustes de stock con motivo; controlados, cuantificados y clasificaciones sin verificar siguen sin ajuste libre. |
| `inventory.order.prepare` | Preparar pedidos; consultar/copiar un pedido aprobado. |
| `inventory.order.approve` | Aprobar pedidos. Preparar no concede aprobar. |
| `sales.collect` | Abrir/cerrar turno propio, cobrar y registrar referencias externas; preparar cargos requiere también lectura clínica. |
| `sales.read` | Consultar caja/cortes y referencias de toda la clínica. No concede cobrar. |
| `cash.move` | Ingreso/retiro/gasto en turno propio, además de `sales.collect`. |
| `sales.reverse` | Reverso con motivo hacia el turno propio, además de `sales.collect`; retornar fármacos a stock conserva la condición profesional/de dispensación de 13I1. |
| `sales.manual` | Captura contable de servicios fuera del catálogo, además de `sales.collect`. No registra ni autoriza un procedimiento clínico. |
| `sales.reconcile` | Conciliar una referencia de pago, además de `sales.read`. No cobra una tarjeta ni vuelve a registrar dinero/stock. |
| `vial.manage` | Vincular un frasco propio a stock, con habilitación profesional vigente. No concede administrar ni extraer. |

Son códigos del catálogo de permisos, sin semillas de concesiones. La administración existente puede elegirlos por persona. La etiqueta de puesto sigue siendo visual. No se cambia una cuenta a MVZ ni se crea evidencia profesional por esta migración.

## Servidor y trazabilidad

Se sustituyen las comprobaciones por puesto de las rutas finales de inventario/caja y referencias de pago. `private.inv_access` consulta `inventory.read`; no queda un OR con el rol anterior para permitir estas operaciones. Los endpoints verifican clínica y actor antes de usar recibos; conservar un recibo exitoso no permite operar con permiso revocado. La captura manual vuelve a comprobar su permiso particular también al repetir el recibo.

La clínica/ledger se bloquean primero. En ventas con receta se bloquean en orden las identidades del actor y responsables antes de comprobar y consumir stock, evitando invertir el orden entre usuarios de varias clínicas. Después se usan los bloqueos existentes de turno, producto y lote. Se comprueba el reloj real tras la espera, no solo la hora de comienzo de la consulta.

`inventory_permission_used` registra concesión, código, actor, clínica, entidad conocida y clave de operación. Los recibos vinculan esa clave al resultado. Reintentar puede conservar otro registro de comprobación de autoridad, pero no duplica la venta, el movimiento, la entrega o la conciliación. Los movimientos y documentos históricos permanecen inmutables; las correcciones de venta siguen siendo reversos, no edición de existencias.

No se añaden tablas ni se convierten históricos en este bloque: se amplía el catálogo de capacidades y se reemplazan funciones/políticas. 13I1 conserva los campos de autoridad del límite de dispensación.

## Lectura y exportación

- Se reemplazan las políticas de lectura del módulo; un administrador sin concesión ya no ve todas las cajas por su puesto. Un cajero con `sales.collect` consulta su turno; `sales.read` abre la consulta global.
- Se retira SELECT directo de `inventory_cash_shifts.snapshot`. Las líneas crudas de venta, cargos y tickets no se entregan directamente al cliente; se consultan mediante RPC con el alcance adecuado.
- Los cortes y el flujo de cobros devuelven información contable: las referencias clínicas se retiran y los cargos por aplicación/entrega/servicio registrado usan rótulos neutros. Esto también se aplica a un corte cerrado anterior, **sin modificar el original almacenado**. Las referencias clínicas permanecen en sus registros de origen.
- `inv_billable_services` sustituye la consulta al agregado antiguo `ops_dashboard` al abrir una venta. Se conservan precios y comisiones del acto ya registrado; cobrar no acredita haberlo realizado.
- Las exportaciones de corte y transacciones vuelven a consultar al servidor antes de generar CSV/PDF/XLSX mediante las herramientas existentes. Si se pierde acceso, no se exporta la copia anterior y se limpia el corte fallido. No se cambia el formato interno por un supuesto documento fiscal.
- Las políticas SQL de fotos comprueban lectura/gestión, clínica, producto y ruta. La inserción de objeto y la asociación de foto serializan con revocaciones; no se permiten sobrescrituras/borrados. MIME, tamaño, red y entrega de archivos reales siguen requiriendo prueba de Storage HTTP.

## Interfaz

Contrato `inv_management_permissions`: `schema_version: 1`, `mode: explicit_inventory`, mapa `actions` y capacidades para frascos/cargos. Flutter muestra cada acción según ese contrato y valida su forma. Perderlo, recibir otra versión o un mapa inválido después de conocerlo bloquea acciones; no vuelve a un puesto como autoridad. Solo conserva compatibilidad con el servidor anterior que nunca lo anunció.

Los accesos de Inventario/Caja/Escáner ya no se ocultan por el puesto de estilista: el servidor decide si esa cuenta puede consultar. Se limpian modelos al cambiar cuenta/clínica. El tablón de entregas y las referencias de pago también consumen las capacidades nuevas. El indicador profesional antiguo del dashboard no sustituye una capacidad nueva.

## Pruebas y límites

`bash supabase/tests/run_permission_inventory_cash.sh` usa PostgreSQL aislado y todas las dependencias 13H/13I1, con fixtures **ficticios**. Prueba:

- Administrador sin concesiones, persona con puesto visual estilista y concesiones explícitas, separación gestionar/recibir/ajustar/cobrar/aprobar/conciliar, acceso ajeno y anónimo.
- Venta, entrada, ajuste, reverso, pedido y consulta; versión de producto; movimientos y suma monetaria; fotos con ruta/políticas; revocación antes de repetir recibos.
- Referencias de pago sin duplicar caja o stock, conciliación separada e idempotente.
- Dispensación profesional tras el corte y cobro por otra persona sin permiso para dispensar.
- Cortes históricos sin revelar referencias clínicas ni reescribir originales; rechazo de tablas/campos crudos; concesión enlazada a la operación auditada.
- Confirmaciones simultáneas: una venta; revocación ganadora bloquea recibo previo; permiso que vence durante una espera no recibe lote ni mueve stock.

Flutter prueba capacidades separadas, puesto sin autoridad automática, pérdida/versión/mapa inválidos, limpieza tras fallo de corte, flujo de venta sin agregado antiguo y facultades distintas de referencias de pago. Resultado local: **312 pruebas Flutter satisfactorias**, análisis sin incidencias y harness PostgreSQL/concurrencia satisfactorio.

No acredita Auth HTTP real, entrega de archivos en teléfono, integración de pasarela, permisos de respaldo/identidad de otros módulos ni aplicación remota. El editor de ajustes por lotes con borrador, resumen antes/después y confirmaciones especiales sigue como trabajo de producto independiente; este bloque no lo simula ni lo declara terminado. Continuar con reportes/formatos y el corte transversal, manteniendo beta cerrada.
