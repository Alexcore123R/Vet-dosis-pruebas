# Producción: primeras herramientas porcinas y acuícolas

## Funciones integradas

Producción y grandes especies → Porcinos → Crecimiento y engorda abre una calculadora de grupo cerrado: peso vivo ganado, ganancia diaria por animal, conversión alimenticia y costo de alimento por kg ganado. Requiere confirmar que los pesos corresponden al mismo grupo sin entradas, salidas ni bajas. Los periodos con movimientos, pérdida de peso o sin ganancia requieren otro modelo y no se calculan aquí. El consumo debe medirse descontando sobrantes y desperdicio. El costo es opcional y solo aparece con acceso a Planeación financiera.

Producción y grandes especies → Peces → Tilapia abre biomasa y ración: peces actuales × peso promedio en gramos / 1000; biomasa × porcentaje diario elegido / 100; división en raciones iguales. No se precargan tasas ni umbrales ambientales. Una tasa explícita de cero produce cero; el resultado no prescribe alimentar.

Ambas herramientas son cálculos de sesión. No guardan unidades, lotes, animales, alimento, tratamientos ni movimientos de caja. Los registros futuros siguen marcados como pendientes. Editar entradas borra el resultado anterior; revocar acceso retira la herramienta, y retirar acceso financiero borra el importe capturado y su resultado. Se reutiliza el permiso existente de Cálculos clínicos.

## Procedencia y alcance

La base porcina está identificada en [revisión del PDF](porcinos-y-planeacion-desde-pdf-20261018.md), página 53 de Cruzas Razas.pdf (UDG/CUCBA). Se comprueba el ejemplo 2320 / (856 − 120) = 3.15217 y 6032 / 736 = 8.19565. Son datos de prueba, no valores precargados. No se interpreta costo de alimento como costo completo de granja ni costo de canal.

La ecuación acuícola procede del requisito aportado: biomasa × tasa de alimentación. Las tablas por talla y temperatura y los límites de agua no se incorporan como verificados.

## Revisión

Pruebas de fórmulas, valores no finitos, divisores inválidos, coma decimal, resultados obsoletos, acceso por rol y eliminación de costos al perder permiso. Previews reproducibles con datos sintéticos en `test/previews/capture_production_tools.dart` y `review/production-tools-20261019/`; no son capturas de un dispositivo físico.

La prueba antigua de dashboard que pulsaba Cálculos en el lateral se adapta a la barra inferior después de retirar aquel acceso duplicado. No se cambia la lógica de permisos ni Supabase.

## Pendiente

Registros persistentes por unidad y lote, movimientos de población, servicios reproductivos y camadas; herramientas específicas de otras especies y exóticos; presupuestos guardados y comparación contra resultados reales. Esta entrega no declara completos esos módulos.
