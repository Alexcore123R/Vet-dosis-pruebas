# Materiales aportados: Porcinos y Planeación financiera

Revisión del 18 de octubre de 2026. Fuente y hash de cada PDF en
[Registro de materiales](fuentes/materiales-porcinos-presupuesto-20261018.json).
Se respeta la declaración de la usuaria de que el material porcino es verificado;
la revisión actual identifica procedencia, campos, contexto y puntos concretos
pendientes de aclaración. No constituye una comprobación externa independiente
ni cambia automáticamente el estado de parámetros operativos de la app.

No se añaden más diseños ni se implementan estos módulos en esta revisión.
Los originales no se copian al repositorio; se conserva su identificación y hash.

## Porcinos: qué contiene realmente Cruzas Razas.pdf

66 páginas. La portada identifica UDG/CUCBA, Departamento de Producción Animal,
Producción de Cerdos y MPP Ivón Yanine Chávez Mora. Hay texto extraíble en 56
páginas y otras láminas basadas en imágenes. Se inspeccionaron visualmente las
páginas 14 y 62 para distinguir problemas del PDF de errores de extracción.

Ruta propuesta: Producción y grandes especies → Porcinos.

| Subapartado | Información aprovechable | Páginas del PDF |
|---|---|---|
| Razas y líneas | Landrace, Large White/Yorkshire, Duroc, Pietrain, Hampshire; características y comparaciones con su contexto | 6, 10, 13–19 |
| Genética y cruzamientos | Estructura de núcleo/multiplicación/producción, esquemas de cruza, progenitores, finalidad y heterosis | 20–38 |
| Reproductores e identificación | Identificación, raza/línea, origen, madre/padre y registro individual | 45–50 |
| Servicios reproductivos | Fecha de servicio/monta, cerda, semental, horas, FPP y observaciones | 49–50 |
| Camadas y maternidad | Nacidos totales/vivos/muertos/momias, adopciones, donaciones, bajas, pesos y destete | 50–51 |
| Alimentación por corral | Corral, día, alimento servido/acumulado y observaciones de consumo | 52 |
| Crecimiento y engorda | Días, animales iniciales/finales, pesos inicial/final, alimento y costo por kg | 53 |
| Indicadores y selección | Objetivos, rasgos, heredabilidad, métodos de selección, índices y ajuste del peso por edad | 41–44, 54–66 |

### Campos de registro propuestos

- **Reproductor:** identificador interno y visible, sexo, raza/línea o composición,
  origen, padres conocidos y unidad. Mantener separados animal, raza y línea comercial.
- **Servicio:** fecha, hembra, semental/material reproductivo cuando corresponda,
  horarios y observaciones. FPP manual; cualquier cálculo posterior requiere un
  parámetro explícito documentado, no deducido de un único ejemplo de fecha.
- **Parto/camada:** madre, padre cuando se conozca, fecha, identificador de camada,
  categorías de nacimientos, movimientos de adopción/donación y observaciones.
  La definición de categorías debe evitar contar una momia en dos totales sin aclararlo.
- **Lechón o lote:** identificación opcional individual, sexo, peso, fecha/edad de
  medición, camada y movimientos. Peso a 21 días y al destete no son campos idénticos.
- **Alimento:** fecha, corral/lote, producto o fase, unidad, cantidad servida y
  medición de sobrante/desperdicio cuando exista. Alimento servido no equivale
  automáticamente a alimento consumido.
- **Engorda:** periodo, animales y biomasa inicial/final, entradas/salidas/bajas,
  alimento del periodo y costos asociados. Con cambios de población no basta
  dividir todo entre el número inicial de cerdos.

Los registros admiten captura parcial y seguimiento posterior. Se pide solo lo
indispensable para el acto registrado; faltantes de una fórmula impiden ese cálculo,
no guardar una observación o completar otros registros.

### Indicadores derivados, sin copiar los resultados del ejemplo

1. Promedio de peso = peso total / animales efectivamente pesados.
2. Ganancia diaria = cambio de peso comparable / días transcurridos.
3. Conversión alimenticia = alimento consumido / ganancia de peso comparable,
   con base de población, periodo y movimientos definidos.
4. Costo de alimento por kg ganado = costo del alimento consumido / ganancia de peso.
5. Supervivencia, mortalidad, destetados y otros indicadores reproductivos con
   numerador, denominador, periodo y tratamiento de adopciones definidos.
6. Índices maternos u otros de selección solo después de documentar fórmula,
   unidades, población de comparación, ajuste y alcance. No implementar BLUP
   como si fuera una operación simple a partir de una diapositiva descriptiva.

### Puntos de cotejo identificados

- **Página 14:** la ganancia diaria de Hampshire está vacía. El rango de lechones
  destetados se ve como «9.5 – 10-5» también en la imagen; no convertir a 10.5 sin
  confirmar la corrección. Los datos faltantes se conservan como desconocidos.
- **Página 62:** Cleveland aparece como «100 + 286.6 (g. p. promedio kg) – 39.4»,
  sin explicar todas las variables/unidades. No completar el término por intuición.
  Iowa también necesita unidades explícitas antes de programar sus coeficientes.
- **Páginas 54–55 y 63:** conservar la notación h/h² y su definición contextual;
  no generar respuesta a la selección sin aclarar qué heredabilidad se está usando.
- **Páginas 6 y 14:** las clasificaciones materna/paterna no deben convertirse en
  una prohibición rígida por raza; el documento ubica Hampshire en ambos contextos.
- **Página 53:** el ejemplo usa 2320 kg de alimento para una ganancia de peso vivo
  de 856−120 = 736 kg. Da conversión 3.15217 y costo de alimento 8.19565 por kg
  ganado a precio 2.60. La app debe rotular la base como **ganancia de peso vivo**;
  no es por sí solo costo completo de carne/canal producida ni costo total de granja.
- Las fotografías y diagramas no se incorporan automáticamente como imágenes de
  catálogo con licencia/procedencia revisada. Su transcripción visual completa queda
  pendiente si se decide implementarlos.

## Planeación financiera: adaptación del formato académico

10 páginas, procedentes de una hoja de cálculo exportada a PDF. Varias columnas
quedaron repartidas entre páginas: no son diez presupuestos independientes.
La plantilla base está en páginas 1–4; el ejemplo de despacho contable en 5–8;
la explicación y ejemplo de capital de trabajo en 9–10. No se identifica autor
individual responsable de la plantilla en su contenido; no se atribuye por metadatos.

Ruta: Administración y finanzas → Planeación financiera → Proyecto/presupuesto.
Sirve para clínica, hospital o unidad productiva; los rubros se personalizan.

| Apartado | Campos y resultados de la app | Fuente |
|---|---|---|
| Proyecto | Nombre, tipo de unidad, ubicación, responsable, periodo/ciclo y moneda | p. 1 |
| Inversión inicial | Infraestructura, equipo, mobiliario, vehículos, otros conceptos y fondo operativo inicial | p. 1 |
| Costos de operación | Rubros fijos/variables o mixtos desglosados; periodo y naturaleza de cada importe | p. 1 |
| Ingresos estimados | Producto/servicio, precio unitario, cantidad estimada y periodo | pp. 1–2 |
| Resultado presupuestado | Ingresos menos costos incluidos, mostrando alcance y conceptos faltantes | p. 2 |
| Fondo operativo | Necesidades de efectivo, fondos disponibles y reserva explícita para contingencias | pp. 5, 7, 9–10 |
| Observaciones | Conclusiones, puntos críticos y estrategias | p. 2 |
| Plan contra real | Comparación posterior con registros reales del mismo periodo y espacio | Propuesta de la app, no función contenida en el PDF |
| Viabilidad/escenarios | Equilibrio y recuperación de inversión con supuestos explícitos | Ampliación propuesta, no cálculo automático incluido en el PDF |

### Ajustes necesarios para una herramienta reutilizable

- Agua, luz, mantenimiento y mano de obra figuran en diferentes categorías. La
  clasificación depende del caso; permitir rubros mixtos desglosados sin contabilizar
  dos veces el mismo gasto.
- Normalizar el periodo antes de sumar importes mensuales, anuales y por ciclo.
- Separar inversión, costo/gasto, financiación y reserva. El fondo operativo
  inicial financia la operación; no se descuenta otra vez como un costo adicional.
- **Depreciación** afecta el resultado contable pero no es una salida de efectivo
  del mes. La estimación de fondos necesarios debe separarla. La tabla de la p. 10
  la incluye en el total de capital de trabajo del ejercicio: preservar el ejemplo
  académico sin replicar esa suma como regla de caja.
- Los **1500** de «monto adicional necesario» del ejemplo se explican como imprevistos
  en p. 7. Tratarlos como reserva propuesta, no como diferencia automática entre
  33500 de costos y 33500 disponibles.
- La aritmética del ejemplo de ingresos cuadra: 5×1500 + 20×500 + 3×2000 = 23500;
  23500−9000−24500 = −10000. Son importes didácticos de un despacho, no tarifas,
  resultados ni fondos precargados de una clínica.
- Aunque la plantilla diga utilidad neta, la interfaz debe indicar **resultado
  estimado con los conceptos capturados** hasta definir impuestos, gastos
  financieros y demás partidas aplicables. Flujo de caja es una vista diferente.
- No convertir un guion de clase o un ejemplo resuelto en movimientos reales de
  caja, precios de venta o resultados de la clínica.

## Entrega de esta revisión

Se incorporan requisitos y procedencia al mapa de secciones, sin diseños nuevos,
archivos clínicos operativos, tablas ni llamadas remotas. No se resuelven los ejercicios
académicos pendientes de índices maternos o selección. Próxima implementación:
registros porcinos y presupuesto por proyecto, en sus rondas funcionales respectivas.
