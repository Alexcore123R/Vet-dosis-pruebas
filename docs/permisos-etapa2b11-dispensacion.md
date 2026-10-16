# 2B-11: dispensación física separada del cobro

Candidato local **13I1**, posterior a 13H3. No desplegar aisladamente, no generar otro APK ni abrir beta. Primer bloque de inventario: la dispensación; la gestión completa de inventario/caja queda para 13I2.

## Se conserva y se corrige

Ya existían entregas, ventas, cantidades máximas por receta, movimientos por lote y separación entre entrega y cobro. Se reutilizan. Se conserva la **última** implementación de `inv_sale_post` de operaciones M9, incluidas aplicaciones, entregas, actos de servicio y comisiones; no se vuelve a la versión inicial M8.

El antiguo `private.inv_dispense` permitía entrega ordinaria por delegación a personal no habilitado. El nuevo exige, para los fármacos que este flujo vincula a receta, MVZ con habilitación vigente, `controlled.dispense`, `inventory.read`, `patient.read` y `clinical.read`. El puesto visual no concede ni elimina estos permisos. Los productos generales conservan su flujo sin receta. No se inventa una categoría de venta libre ni una lista normativa de controlados.

`inv_delivery_prepare` aplica esta condición directamente; la venta de stock la aplica a través de `private.inv_dispense`. Repetir una operación exitosa vuelve a comprobar autoridad y límite vigentes antes de devolver el recibo. El cobro de un ticket ya entregado no exige permiso clínico ni vuelve a descontar stock. Una devolución de venta que **sí** retorna fármacos a stock exige habilitación y permiso además de las condiciones actuales de devolución/caja.

`inv_delivery_grant` queda cerrado. Los registros anteriores se conservan y su dueño actual todavía puede revocarlos, incluso sin mantener habilitación; no se convierten en permisos nuevos. La autorización temporal de recetas de 13H3 tampoco concede dispensación.

## Cantidad y trazabilidad

Se añaden a `inventory_dispensing_limits`:

- `permission_grant_id`: concesión exacta usada por el responsable.
- `member_since`: pertenencia a la clínica al autorizar.
- `profile_version_id`: versión del perfil responsable.

La restricción exige el conjunto completo o NULL histórico. Un límite anterior sin autoridad nueva requiere revisión explícita; no se migra automáticamente. El MVZ responsable autoriza la cantidad **total en unidades de stock**, con vencimiento y motivo; no se deduce de una dosis en mg/ml ni se convierte de volumen a envases automáticamente. Cero conserva el significado de retirar la cantidad autorizada.

La entrega exige receta emitida, presentación exacta, clasificación/fuente verificadas, límite vigente y pertenencia/permisos/perfil actuales del otorgante. Los productos cuantificados/controlados mantienen el folio capturado y la lectura restringida del flujo de recetas. No se añaden normas ni datos de prototipos. La referencia congelada del movimiento conserva la concesión del autorizador y la del dispensador, el actor, receta, clasificación y cantidad.

Se suma lo entregado por tickets y lo vendido directamente, excluyendo solo los reversos de venta que ya devolvieron stock. Clínica/ledger serializan autorización, entrega, venta y revocación; se bloquean identidades del actor/responsable y se comprueba tiempo real después de esperar. No se permite sobrepasar el total mediante dos rutas simultáneas.

Como protección adicional, `inv_stock_adjust` requiere `inventory.adjust` y rechaza ajustes libres de fármacos controlados, cuantificados o sin clasificación verificada. No sustituye todavía el futuro borrador por lotes, resumen antes/después y confirmación adicional.

## Interfaz

Contrato `inv_dispensing_permissions`, `schema_version: 1`, `mode: verified_dispensing`. Flutter usa la capacidad de servidor para autorizar cantidad, mostrar entrega y ofrecer fármacos como stock en la venta. Cobros de entregas/aplicaciones permanecen separados. Al conocer el contrato, perderlo o recibir otra versión bloquea estas acciones; solo se conserva compatibilidad con un servidor anterior que nunca lo anunció. Se descarta el estado al cambiar de cuenta/clínica y se ignoran respuestas antiguas de cargas simultáneas.

Las delegaciones antiguas dejan de ofrecerse en el flujo nuevo. No se hereda `professional` del dashboard ni un puesto como sustituto del contrato nuevo.

## Validación

`bash supabase/tests/run_permission_dispensing.sh` crea PostgreSQL aislado y aplica primero dependencias/pruebas 13H. Los productos, documentos y fuentes verificados son **fixtures ficticios**, nunca datos de producción.

Prueba profesional sin permiso, permiso sin habilitación (fixture adversarial), cambio de puesto visual, cantidades históricas sin conversión, cambio de versión de perfil, ordinario y controlado, clasificación/receta exacta, límite acumulado, cobro sin segundo descuento, recibos repetidos y revocados, ajustes libres de controlados y acceso anónimo. La carrera entrega versus venta comprueba que solo se consume una unidad restante; revocar primero bloquea el recibo anterior.

Resultado local: **302 pruebas Flutter satisfactorias**, análisis sin incidencias y harness PostgreSQL satisfactorio. Incluye entrega contra venta simultánea, revocación previa al recibo y vencimiento del permiso mientras la operación espera el bloqueo, sin mover stock.

Flutter comprueba prioridad del contrato sobre el indicador profesional antiguo, pérdida/versión desconocida, ocultación de delegación y entrega no permitidas, y entrega explícita sin volver a habilitar delegación. La prueba local no acredita HTTP/Storage/Edge ni teléfono físico.

## Pendiente concreto: 13I2

Este candidato **no termina todo inventario**. `inv_access`, el dashboard, políticas de lectura de movimientos/documentos, caja, catálogos/precios, proveedores/pedidos, fotos/Storage, preparación de cargos, enlace de frascos y parte de la navegación todavía necesitan sustituir sus dependencias antiguas. La venta conserva las condiciones actuales de caja/puesto **para cobrar**, además del candado nuevo independiente **para dispensar**. No afirmar que todos los permisos financieros o lecturas del módulo estén migrados.

Luego siguen reportes/formatos y el corte integral con Auth real, dos cuentas/clínicas, archivos y Edge. Este bloque no activa admisiones, no aplica cambios al servidor y no introduce borrado automático.
