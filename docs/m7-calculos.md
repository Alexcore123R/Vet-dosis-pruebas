# M7: cálculos clínicos

Implementado localmente en `lib/modules/calculations`, accesible desde **Cálculos clínicos** en el menú. MVVM, repositorio inyectable y lógica pura independiente de Flutter. No crea tablas ni modifica Supabase.

## Herramientas

| Herramienta | Entradas explícitas | Resultado |
|---|---|---|
| Fluidoterapia | kg, mantenimiento indicado ml/kg/día, porcentaje estimado de deshidratación, horas, pérdidas totales del periodo en ml y gotas/ml del equipo | Mantenimiento diario, déficit estimado, volumen del periodo, ml/h y gotas/min teóricas |
| CRI | kg, dosis indicada mcg/kg/min, concentración comercial mg/ml, volumen final ml, bomba ml/h y gotas/ml | mg/h, duración, mg totales, ml de fármaco, ml de diluyente, concentración final y goteo |
| Lote/cabeza | Peso por cabeza kg, número entero de animales, mg/kg indicados y mg/ml | mg y ml por cabeza y por lote |
| Agua | mg de activo/L indicados, litros y potencia mg de activo/g de producto | mg de activo y gramos de producto |
| Alimento | mg de activo/kg de alimento indicados, toneladas métricas y potencia mg/g | mg de activo y gramos de producto |
| Ajuste por edad/condición | Referencia específica verificada de fármaco, especie, condición, presentación y factor; kg, dosis inicial y concentración | Ajuste matemático únicamente si la presentación y el rango verificados corresponden |

No hay tasas de mantenimiento, porcentajes, factores de equipo, dosis ni factores por edad predeterminados. En fluidoterapia, el déficit usa la aproximación explícita de 1000 ml de agua por kg; las pérdidas son el volumen total del periodo, no una tasa. El volumen de CRI es **final e incluye el fármaco**. Si el fármaco supera ese volumen, el cálculo se rechaza. La mezcla no se autoriza por compatibilidad, estabilidad o vía: corresponde revisarlas al MVZ.

En agua no se interpreta automáticamente la palabra ppm: la entrada exige mg/L. En alimento no se infiere la ingesta individual. El cálculo por lote usa peso uniforme estimado y no sustituye pesar a cada animal.

## Referencias versionadas

`assets/clinical/calculations.v1.json` contiene la definición de campos/unidades de las herramientas y una lista de referencias deliberadamente vacía. Las operaciones dimensionales se implementan en código y se comprueban con vectores matemáticos; cambiar su significado requiere una versión compatible del motor, no evaluar texto de JSON como código.

Cada referencia requiere `id`, `tipo`, `titulo`, `especie`, `fuente` y `estado` (`verificada` o `sin verificar`). Una referencia marcada verificada sin fuente se rechaza. Las cantidades son cadenas decimales; no notación científica. Los valores clínicos faltantes permanecen nulos. No se distribuyen las cifras sintéticas de las pruebas.

- `constante`: `parametro`, `unidad`, `min`, `max`. Los límites son inclusivos. La pantalla evalúa mientras se captura y marca en rojo valores fuera de rango; no diagnostica. Sin ambos límites y fuente verificada no clasifica.
- `protocolo`: `etapas`, cada una con `etapa` (premedicacion/induccion/analgesia/recuperacion), `dosis_id`, `presentacion_id`, `dosis_mg_kg`. Usa la especie y los IDs exactos del catálogo M3. Calcula masa/volumen y graduación con el motor M3, conservando alertas de rango, redondeo, contraindicación y fuente. Un reversor debe figurar expresamente como etapa con su referencia; no se inventa proporción. No evalúa automáticamente interacciones entre fármacos.
- `metabolico`: `exponente` específico, dentro del intervalo matemático (0,1]. Calcula solo kg elevado a ese exponente, con resultado aproximado. **No escala dosis entre especies ni convierte ese resultado en mg o ml.**
- `ajuste`: `farmaco_id`, `presentacion_id`, `condicion`, `factor`. Requiere fuente verificada y rango M3 de la especie; la concentración capturada debe coincidir con esa presentación verificada y el ajuste debe quedar dentro del rango. No utiliza una regla universal para pacientes pediátricos o geriátricos.
- `retiro`: `producto_id`, `presentacion`, `via`, `destino`, `jurisdiccion: MX`, `tiempo`, `unidad: horas/dias`. Se muestra la referencia comercial exacta; no se traslada un tiempo entre productos, vías, especies o destinos. Cero es un valor explícito diferente de desconocido. No se calcula una fecha de liberación ni se autoriza comercialización.

Las referencias se incorporan al JSON y se revisan antes de distribuir una nueva versión. No hay editor/importador M7 en la app en esta entrega. Protocolos y referencias siguen sin datos hasta contar con fuentes reales.

## Uso y controles

Los resultados racionales mantienen aritmética exacta internamente. La pantalla muestra hasta nueve decimales y advierte que son una visualización aproximada. Un resultado positivo menor que esa precisión se muestra como `<0,000000001`, nunca como un falso cero. No redondea a gotas enteras ni asume graduación de jeringa para CRI/producción.

Cambiar cualquier entrada invalida el resultado y la revisión. Hay revisión expresa de parámetros seguida de confirmación, sin emitir receta ni administrar medicamento. Protocolos con alertas no permiten confirmación. Los parámetros solo viven en memoria; no se persisten, no contienen identificadores de pacientes y no se agregan automáticamente al expediente, hospitalización o controlados.

El acceso sigue el permiso de cálculo M3 (MVZ/admin); esto no otorga habilitación para actos reservados de M6. Las referencias locales funcionan sin conexión. No se solicita ni cambia el rol mediante un selector.

## Verificación y pendientes

Pruebas con valores sintéticos de resultado conocido: periodos de fluidoterapia, pérdidas, CRI y volumen final, frascos diluidos inválidos, lote entero, conversión agua/alimento, precisión pequeña, extremos inclusivos, referencias ausentes, especies/presentaciones M3, protocolos fuera de rango, metabolismo y ajustes con fuente. Prueba de interfaz a 390 × 844: cálculo, invalidación por edición y referencia ausente, sin excepción de diseño.

Pendiente: fuentes reales, revisión clínica de parámetros y reglas, editor/importación de referencias, referencias de retirada completas, prueba con pacientes/datos reales, integración revisada del resultado con M6 y pruebas Android/iPhone. Véase [lista central de pendientes](pendientes-revision-final.md).

Comprobación de esta entrega: `flutter analyze` sin incidencias, `flutter test` con 96 pruebas aprobadas (14 de M7) y compilación web configurada generada en `build/web`. Sin pruebas nativas ni cambios al servidor remoto.
