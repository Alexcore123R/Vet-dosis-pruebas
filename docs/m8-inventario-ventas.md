# M8: inventario, ventas y caja

Implementación local en Flutter/Supabase. Se conservan `inventario` y `lotes_inventario`, con adaptación aditiva. No se ha instalado M8 en Supabase remoto ni probado cámara/caja con registros reales.

## Inventario y lotes

El admin registra productos, presentación, tipo (producto no farmacológico o fármaco), unidad de stock, precio final MXN, costo de referencia, stock mínimo, punto de reorden, proveedor y código. Los lotes conservan número, caducidad DATE, cantidad y costo unitario. El costo de una venta corresponde al lote elegido, no al costo editable del producto.

Entradas, ajustes con motivo, ventas, reversos y envases abiertos quedan en un libro de movimientos inmutable. El balance se actualiza dentro de la misma transacción. No se puede cambiar stock mediante las tablas antiguas desde el cliente. Los lotes se seleccionan explícitamente y se presentan por caducidad; no se mezclan sin avisar.

Se muestran stock total y disponible. Disponible excluye lotes vencidos y fármacos sin fecha; mínimo/reorden usan ese saldo disponible. Alertas a ≤30/≤60 días. La dispensación se bloquea **desde el día de caducidad capturado**, según la zona horaria configurada para la clínica. Es una regla conservadora del producto, no interpretación automática de etiquetas con solo mes/año. No se convierte la caducidad textual antigua a una fecha inventada.

Los registros anteriores quedan sin habilitar hasta revisar clasificación, unidad y concordancia entre stock y lotes. `inv_enable_legacy` conserva saldos y agrega apertura de libro; si hay discordancia, cantidades negativas o costos no aptos, se bloquea la adopción y exige conciliación de migración. Los registros personales con clínica nula se conservan, pero no se trasladan ni se exponen en el inventario de otra clínica. La gestión de inventario personal independiente sigue pendiente.

La identidad de producto/unidad/referencia farmacológica queda congelada al habilitarlo; precios y datos descriptivos pueden cambiar con control de versión. Una nueva versión del catálogo que invalide la referencia anterior bloquea dispensación: todavía falta un flujo revisado para actualizar esa vinculación sin reescribir ventas históricas.

## Venta y dispensación

Admin, MVZ, auxiliar y recepción pueden operar su propia caja para productos no farmacológicos. Estilista no tiene acceso a este módulo. Entradas/precios/ajustes/pedidos requieren admin; estar en ese rol no concede habilitación profesional.

El servidor bloquea simultáneamente los productos y lotes en orden estable, comprueba cantidades, caducidad, precio y total, y registra venta y descuento juntos. Dos cajas no pueden vender la última unidad dos veces. Un reintento con el mismo identificador no duplica venta, movimiento o cobro registrado. Envases/cajas/unidades exigen cantidades enteras; g/kg/ml/L admiten cantidades exactas. No se hacen conversiones implícitas de envase a dosis.

Para fármacos se exige versión comercial verificada vigente y receta emitida que coincida. Controlados/restringidos/receta cuantificada solo los dispensa un MVZ habilitado en servidor, conservando el folio manual de la receta. Auxiliar puede dispensar un producto ordinario verificado con acceso al caso y permiso vigente del MVZ responsable. Recepción también puede entregar ordinarios mediante el permiso específico revocable del MVZ responsable incorporado en el ajuste descrito abajo. Admin sin habilitación no dispensa fármacos con ese flujo. La app no deduce una clasificación legal a partir del nombre, código o foto.

El MVZ responsable autoriza además la **cantidad total de stock** a dispensar por medicamento de receta, con vigencia y motivo. La suma de ventas no revertidas no puede superar ese total. Cero revoca el límite; actualizarlo agrega otra versión. No se interpreta la dosis por administración de M6 como cantidad total de frascos/cajas. El permiso de auxiliar se vuelve a revisar al vender y una firma compartida no lo sustituye.

Las líneas congelan nombre, lote, unidad, cantidad, precio, costo, comisión y referencia de dispensación. Un cambio de precio posterior no cambia un recibo anterior. La venta es un registro interno con método efectivo/tarjeta/transferencia; no cobra mediante pasarela ni genera CFDI. El precio capturado es final, sin calcular IVA ni declarar tratamientos fiscales.

El admin puede capturar un servicio manual, costo total y comisión total MXN con profesional identificado. El catálogo y reglas porcentuales/bonos automáticos se conectan con M9; no se inventan tarifas.

## Caja y reversos

La entrega clínica y la administración se separan del cobro: ver el ajuste siguiente. Cada cajero abre un turno con fondo inicial y hora del servidor. Los ingresos adicionales, retiros y gastos en efectivo se capturan aparte con motivo; ingresos/retiros no se presentan como ventas o utilidad. El corte muestra ventas menos reversos, métodos de pago, costo, comisiones, margen y resultado con **gastos capturados**. Este último no certifica que se hayan registrado todos los gastos de la clínica. Otros gastos, impuestos y costos financieros no se infieren.

El cierre exige efectivo contado y motivo si difiere del esperado. Conserva el corte exacto e inmutable; ventas posteriores a ese turno se bloquean. El admin ve el resumen del día por zona horaria y los turnos de la clínica; los demás solo sus datos de caja, incluso si intentan leer las tablas directamente.

Un reverso completo exige admin, turno propio abierto y motivo; devuelve físicamente el stock al lote original y reconoce el reverso en el turno actual. No cambia el corte cerrado original. Un lote devuelto ya caducado permanece bloqueado para venta. Reversos de controlados exigen además habilitación profesional. Las devoluciones parciales, devoluciones no revendibles, nota de crédito fiscal y reembolsos por pasarela no están implementados.

Exportación del corte a CSV UTF-8 para Excel, con importes exactos y neutralización de fórmulas en texto. No es XLSX ni reporte fiscal; el archivo descargado queda bajo control del usuario.

## Frascos, cámara y fotos

Un MVZ responsable vincula un frasco M6 con el producto/lote exactos y la cantidad entera de envases abiertos. Esa operación resta envases de M8 una sola vez; las tomas posteriores restan volumen únicamente del frasco M6. Se mantiene la relación en tabla adicional; no se modifica el registro original del frasco ni se supone su volumen por presentación. Conciliar un frasco M6 no ajusta automáticamente el stock físico M8.

`mobile_scanner` lee códigos con cámara en Android/iOS/web y lleva el resultado a búsqueda. Un código no identifica clínicamente concentración o dosis. También hay entrada manual. En web, cámara exige un contexto seguro y permisos del navegador; el lector puede necesitar cargar su biblioteca de decodificación. No se ha probado cámara real en esta entrega.

`image_picker` captura/selecciona una foto JPEG/PNG para identificación. Se limita a 4 MB; Storage usa un bucket privado con rutas por clínica/producto. Solo admin sube/adjunta, las fotografías no se sobrescriben, y los enlaces firmados duran 60 segundos. No se realiza OCR ni se completa automáticamente el catálogo farmacológico con una foto. La autorización de un enlace ya emitido puede seguir vigente hasta su expiración. Archivos subidos sin adjuntar por conflicto necesitan limpieza privilegiada posterior; no se borra el historial de fotos automáticamente.

## Pedidos y resurtimiento

Un borrador toma nombres/presentaciones y stock disponible de productos activos en reorden. Las cantidades propuestas quedan **por revisar**. La pantalla muestra también productos con mayor importe vendido neto de reversos en los últimos 30 días del calendario de la clínica; no es una predicción de demanda.

El admin edita proveedor/texto y luego aprueba la versión exacta. No hay envío automático. Solo tras aprobar se habilita copiar o abrir `wa.me` con número ingresado y mensaje prellenado; el envío lo realiza la persona. La redacción con proveedor de IA y comparación de precios de mercado siguen pendientes, sin recomendaciones o precios inventados.

## Instalación y pruebas

- `existing_inventory_m8.sql`, una vez después de M6 y sus dependencias. Revisar respaldo/esquema real: aborta si un lote antiguo pertenece a otra clínica que su producto. Revoca escrituras directas de tablas antiguas y expone RPCs concretas.
- `existing_inventory_photos_m8.sql`, una vez después de M8 en un proyecto con Supabase Storage. Crea bucket/políticas privados y la operación de adjuntar. Sin esta adaptación, stock/caja funcionan y las fotos informan que falta configuración.
- Pruebas SQL: `bash supabase/tests/run.sh inventory`. PostgreSQL aislado sin red, fixtures sintéticos: importes, stock, caducidad, reintentos, cierre/reversos congelados, admin/auxiliar sin actos reservados, límite acumulado, delegación revocada, servicios/comisiones, frascos, fotos por clínica y dos cajas concurrentes. El harness de Storage comprueba políticas; no reemplaza al servicio binario real.
- Flutter: aritmética exacta de centavos, CSV seguro, limpieza de datos ante fallos/respuestas tardías, permisos visibles, diseño de celular y carrito revisado con lote/importe exactos. Compilación web local; dispositivos nativos pendientes.

Estado offline: stock/caja requieren conexión. No se persisten datos financieros ni fotografías en la caché sin cifrar. Son pendientes finales: instalación real, fuentes regulatorias y prueba integrada con usuarios, dispositivos, cámara/galería, fotos y CSV; también conciliación legacy, actualización revisada de referencias, inventario personal, devoluciones parciales, IA/mercado, XLSX y M9/M11. Ver [lista central](pendientes-revision-final.md).

Verificación de esta entrega: análisis Flutter limpio, 107 pruebas aprobadas (11 nuevas de M8), suite SQL/Storage/concurrencia aprobada y compilación web configurada generada. Sin cambios al proyecto Supabase remoto.


## Ajuste al flujo real de la clínica (8 de octubre)

Una receta es un plan de tratamiento, no una venta de un solo uso. Cada aplicación realizada puede conservar la misma receta y generar un cargo distinto. No se crea una receta nueva ni se vende otro frasco para cobrar la siguiente puesta.

- El auxiliar mantiene los permisos para preparar/emitir recetas ordinarias y registrar aplicaciones según las delegaciones y procedimientos M6. El permiso vigente no exige presencia del MVZ en cada actuación. Las restricciones específicas de actos reservados de controlados permanecen.
- El MVZ habilitado puede conceder a auxiliar o recepción un permiso **de entrega ordinaria** para las recetas bajo su responsabilidad en la clínica. Puede establecer vencimiento o dejarlo vigente hasta revocación. No concede acceso al expediente completo, permisos de receta, firma o actos reservados. Se vuelve a revisar al entregar.
- Una **entrega física** descuenta el producto/lote, registra quién entregó y conserva la autorización, receta y cantidades. Genera una cuenta por cobrar. Quien dispensa un controlado conserva el permiso reservado; otra persona puede cobrar esa entrega ya registrada.
- Una **aplicación clínica** se registra una sola vez en M6 con medicamento, cantidad real, lote, aplicador y hora. Un frasco abierto ya vinculado resta volumen por cada toma y descuenta su envase en M8 una sola vez. La tarifa por aplicación es capturada por el admin, independiente del precio del frasco.
- La persona autorizada en el caso prepara el cargo de la aplicación registrada. Puede estar pendiente la revisión clínica: **preparar o cobrar un cargo no valida una aplicación ni emite un reporte oficial**. El costo se calcula desde el lote/envase y el volumen inicial medido cuando existe vínculo; sin ese vínculo queda explícitamente pendiente y no acredita utilidad definitiva.
- Auxiliar/recepción/cajero cobran las cuentas preparadas desde Nueva venta. La línea financiera no vuelve a descontar ni volumen ni envases. Un cargo o entrega no se cobra dos veces mientras tenga un cobro activo; corregir un registro clínico no crea otro cargo para la misma aplicación original.

Flujo de ejemplo sin cifras clínicas: **receta → primera aplicación registrada → cargo/cobro → siguiente aplicación bajo la misma receta → cargo/cobro**. No se interpreta automáticamente un texto de duración para inventar fechas, número de aplicaciones o una dosis. Se conservan las capturas del responsable.

Adaptación adicional: `existing_inventory_workflow_m8.sql`, una sola vez después de M8. Añade permisos de entrega, tarifas/cargos y cuentas por entregas; conserva las tablas anteriores y extiende sus RPCs. La pantalla Entregas, aplicaciones y permisos conecta este flujo con caja. Las explicaciones sobre enseñanza y responsabilidad no se incorporan como registros ni como afirmaciones legales de la app.

Límites específicos: la devolución financiera de una aplicación no deshace un acto realizado ni restaura medicamento. Los tickets de entrega separados todavía requieren un flujo de devolución física enlazado; un reverso de cobro no devuelve automáticamente su stock ni libera la cantidad clínica autorizada. Tampoco se recalcula un cargo histórico al corregir la aplicación o vincular posteriormente el costo: hace falta una rectificación contable explícita. Estos casos quedan en la revisión final.

Verificación del ajuste: dos aplicaciones con la misma receta cobradas por recepción; descuento de un envase y solo el volumen real de ambas tomas; entrega ordinaria delegada; cobro por recepción de una entrega controlada registrada por MVZ; revocación y bloqueo de cobro duplicado. Prueba de interfaz de carrito sin referencias de stock en los cargos por aplicación. Sin cambios al proyecto remoto.
