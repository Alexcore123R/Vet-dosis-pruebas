# Producción y grandes especies — menú por especie y actividad

Propuesta a partir de la solicitud de la usuaria: seleccionar esta área abre un
segundo menú por especie/grupo, con funciones pertinentes dentro de cada uno.
Solo organización; no se modifican rutas, backend, permisos ni parámetros clínicos.

## Entrada y contexto

Nombre propuesto del área: **Producción y grandes especies**. Aves, peces y abejas
entran por su actividad productiva; equinos y bovinos también pueden tener atención
individual. El área Exóticos conserva la atención de aves/peces de compañía.

Ruta de ejemplo: espacio activo → Producción y grandes especies → Aves → Postura.
Un encabezado/breadcrumb conserva espacio, especie y actividad visibles. Cambiar
especie o actividad no cambia clínica, permisos ni propiedad de registros.

## Segundo menú

| Entrada | Elección de actividad o sistema | Registros principales |
|---|---|---|
| Bovinos | Leche, carne/engorda, doble propósito, atención individual | Animales, hatos/lotes, unidades y ciclos |
| Ovinos y caprinos | Primero identificar ovino/caprino; después carne, leche, reproducción y fibra cuando aplique | Animales, rebaños/lotes, unidades y ciclos |
| Aves | Postura, engorda, reproducción e incubación | Especie aviar identificada, parvadas/lotes, casetas y ciclos; huevos/muestras para incubación |
| Peces | Especie cultivada (tilapia como material inicial); sistema de cultivo capturado en la unidad | Lotes, estanques/tanques/jaulas, biomasa y ciclos |
| Abejas | Apiarios, colmenas, reproducción y cosechas según el flujo | Apiario, colmena, revisiones y ciclos |
| Porcinos | Reproducción/gestación, maternidad, destete, crecimiento/engorda | UPP/granja, animales reproductores, camadas/lotes y ciclos |
| Equinos | Atención individual, reproducción/crianza y actividad según el caso | Animal, establecimiento, atención y seguimiento |

Aves no implica que las mismas tablas sirvan para todas las especies. En cada
unidad se conserva la especie concreta y la finalidad; las referencias llevan su
alcance. «Otros» puede ser extensible después de definir requisitos, sin fabricar
herramientas genéricas para una especie no soportada.

## Secciones dentro de una actividad

Una estructura común, con contenido contextual, evita duplicar la app por especie:

- Resumen de unidad/animales/grupo y tareas pendientes.
- Registros y seguimiento: individuales, grupales o ambos según el trabajo.
- Agenda y tareas de la actividad.
- Sanidad, reproducción y alimentación cuando correspondan.
- Instalaciones/equipos y calculadoras disponibles.
- Inventario y movimientos, enlazados al inventario del mismo espacio.
- Costos e indicadores, enlazados a Administración y finanzas con filtros de
  unidad, especie, grupo o ciclo; supuestos separados de resultados reales.
- Referencias: fuente, contexto, unidad, especie y estado de revisión.

No hay que llenar todo para registrar una observación o atención. Cada calculadora
pide únicamente las entradas indispensables para su fórmula. No se convierten
protocolos de clase en formularios obligatorios de campo.

## Dónde ubicar los materiales aportados

| Material | Ubicación y tratamiento |
|---|---|
| Capacidad/equipos avícolas | Aves → Postura → Instalaciones y equipos, conservando alcance de etapas y referencias. No extrapolar a engorda |
| Incubación | Aves → Reproducción e incubación. Enlace contextual desde postura/engorda si corresponde, con el mismo módulo |
| Apuntes de tilapia | Peces → Tilapia → Calidad del agua y alimentación; pendientes de integración y revisión documental |
| Silos y reservas | Alimentación → Almacenamiento y reservas, compartido por las actividades pertinentes |
| Razas bovinas | Bovinos → Referencias, con documentos específicos y procedencia; imágenes recibidas no se asumen verificadas |
| Guion UPP porcina | Porcinos → Indicadores y seguimiento. Define campos/formulas; no aporta resultados ni resuelve la tarea académica |
| NOM-194/rastros | Instalaciones y bioseguridad → Listas de verificación, solo donde su alcance aplique; verificar versión/fuente antes de uso normativo |
| Microbiología de superficies | Bioseguridad/higiene → Muestreo de superficies; fórmula de UFC/cm² separada de límites de aceptación normativos |
| Presupuestos de curso | Administración y finanzas → Planeación, reutilizable con contexto de clínica o unidad productiva |
| Vitaminas/minerales y nutrición acuícola | Biblioteca de referencias e investigación; no parámetros de alimentación precargados por defecto |
| Portafolio clínico | Requisitos de atención y captura flexible de la app; no referencia universal para toda producción |

El motor de listas puede reutilizar estructura, evidencias y acciones correctivas
para limpieza/turnos/aislamiento con plantillas propias. Una lista de rastros no se
aplica como norma general a clínicas. Una puntuación tampoco acredita certificación.

## Tratamiento de datos y fórmulas

- Conservar valores, rangos, unidades, especie, etapa/sistema y fuente como datos
  sin verificar hasta su revisión. Correcciones de clase y cambios de fuente se
  versionan; no se sobrescriben silenciosamente.
- Avicultura: capacidad redondeada hacia abajo por superficie independiente;
  equipos hacia arriba. El valor de diseño se elige expresamente y el cálculo
  muestra su procedimiento. Equipos y etapas no se homologan por suposición.
- Incubación: distinguir sala/ambiente, incubadora/nacedora, aire/cáscara, especie,
  tipo de equipo, etapa embrionaria y duración. El documento resumido mezcla
  contextos que requieren cotejo; no crear alarmas a partir del resumen.
- Agua: reglas de reducir/suspender alimentación y alertas requieren fuentes
  concretas y alcance. Para concentración NH3 se necesita amoniaco total medido,
  base de unidades, pH/temperatura y ecuación adecuada al agua/salinidad aplicable.
  No confundir NH3 con NH3-N ni NH4+, ni decidir solo con pH y temperatura.
- Silos: geometría y conversión de unidades separadas de supuestos. Densidad,
  rendimiento por hectárea, consumo diario y número de días son entradas
  documentadas del escenario; los ejemplos de clase no se fijan como constantes
  universales. Densidad corresponde a masa/volumen (p. ej., kg/m³).
- Indicadores: cada uno requiere numerador, denominador, unidad, periodo y alcance.
  No rellenar tasas o resultados de una UPP sin registros reales.

## Estado contrastado con el repositorio

Confirmado: `lib/modules/aviculture` y `lib/modules/incubation`, con entradas desde
Grandes especies / Producción → Cálculos clínicos. Assets avícolas de capacidad y
equipos conservan fuente/estado sin_verificar. Incubación tiene cálculos y
referencias, sin convertirlos en un control automático de ambiente.

Ver `docs/m-avicultura-fase1.md` y `docs/m-incubacion-fase1.md`. Su existencia no
acredita producción completa: lotes, ciclos, medicación de grupos y todos los
registros de granja no se dan por instalados. No se localizaron módulos operativos
de acuicultura, silos, apicultura o gestión UPP porcina en los archivos revisados.

## Secuencia propuesta

1. Incorporar este mapa a la revisión de secciones y etiquetar sus entradas como
   existentes, parciales o propuestas antes de cambiar navegación.
2. Planear el submenú y los enlaces a Avicultura/Incubación ya existentes; comprobar
   filtros de acceso, regreso, selección de espacio y borradores al implementarlo.
3. Diseñar unidad/grupo/ciclo con trazabilidad antes de añadir indicadores por lote.
4. Integrar materiales por actividad y fuente, sin habilitar límites clínicos,
   productivos o normativos por el mero hecho de crear una pantalla.

## Material porcino y financiero recibido después

`Cruzas Razas.pdf` aporta registros concretos de reproductores, servicios, camadas,
alimentación y engorda, además de razas y genética. El formato académico de
presupuesto aporta la estructura de planeación por proyecto. La extracción por
página, requisitos y puntos de cotejo están en
[Porcinos y Planeación desde los PDF](porcinos-y-planeacion-desde-pdf-20261018.md).
Esto amplía las fuentes disponibles, sin declarar implementados esos módulos.
