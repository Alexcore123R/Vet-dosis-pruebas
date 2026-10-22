# VetDosis — dosificación por ficha comercial y fracciones de tableta

**Corte:** 2026-10-22. Rama base: `feature/historia-carnet-20261020`.

## Dos vademécums distintos

- **Farmacológico:** mg/kg o unidad del principio activo, concentración del fármaco, rango/reglas clínicas, cautelas y confirmación. Se conserva el motor actual `DoseEngine`.
- **Comercial:** se elige la formulación/ presentación de una **marca específica**, se lee la dosis que indica su empaque o ficha técnica, se introduce el peso del paciente y se calcula la cantidad **en la unidad comercial de esa formulación**. No se infiere la dosis desde el principio activo.

## Implementación de la primera fase

- Pantalla Flutter separada «Vademécum comercial», enlazada desde `DoseScreen`. No cambia las rutas ni el motor farmacológico.
- Admite, tras transcribir etiqueta, **únicamente reglas estrictamente proporcionales al peso**: cantidad de producto / kg indicados en empaque. Unidades: mL, tableta, cápsula, gotas, sobre, g, mg, UI. Conserva peso y cantidad con racionales exactos `Quantity`.
- Para tabletas, da desglose **enteras + parte**: p. ej. *2 tabletas + 1/2 de tableta*, *1 tableta + 1/4 de tableta*, *3/4 de tableta*, **solo si la presentación permite esa partición**. Opciones mitades, cuartos y octavos se seleccionan explícitamente tras confirmar divisibilidad de esa presentación. Inicialmente no se permite fraccionamiento.
- Si la cantidad exacta no corresponde a la partición admitida, muestra advertencia y **no redondea** ni propone un corte diferente.
- La confirmación de proporcionalidad, especie, vía e intervalo es explícita; las cantidades se **transcriben manualmente** hasta que tengamos etiquetas individuales cotejadas. El resultado es aritmético y no receta, registro de administración, ni recomendación de partir tabletas contraindicadas por fabricante.
- Los valores del catálogo PLM no se mezclan con posologías autorizadas; las 1,384 fichas están en la zona privada `vetdosis_reference_staging` y solo 10 han sido cotejadas a nivel de ficha individual, sin revisión clínica definitiva.
- El test `test/commercial_package_dose_test.dart` cubre mitades, cuartos, tres cuartos, enteras, dosis sin división permitida, fracción imposible, unidades líquidas y validaciones de entradas. **Tests pendientes de ejecutar**: Flutter/Dart no disponibles en este entorno.

## Fases siguientes

1. Añadir tabla separada **posología comercial por producto/presentación/especie** con texto literal de fabricante, fecha, URL de fuente, tipo de regla, cantidades, unidades, limitaciones y aprobación editorial/MVZ; no alterar `commercial_products_intake`.
2. Verificar la posología de cada producto en envase o ficha individual **por formulación**. Marcar explícitamente aptitud para dividir tabletas, advertencias de recubrimiento/liberación modificada, incompatibilidades, tiempo de retiro, especies, vía y pauta.
3. Crear motores **distintos** para: instrucciones por bandas de peso, dosis fijas por animal y esquemas particulares; nunca aplicar fórmula lineal a una tabla escalonada. Dejar como «consulta sin cálculo automático» los casos no soportados.
4. Conectar exclusivamente pautas revisadas a este módulo; búsqueda comercial desde el repositorio aprobado, no directamente desde staging privado.
5. Comparar para cada producto la presentación/dosis publicada con su propia etiqueta, bloquear fraccionamiento o cálculo cuando exista contradicción y validar toda pantalla con tests de teléfono compacto y escenarios clínicos sintéticos.

Los rangos fisiológicos/laboratorio seguirán conectándose a sus propios apartados: monitor de constantes, análisis clínicos, expediente y módulos de especie. No se utilizarán rangos no revisados para clasificar un resultado como normal o anormal.
