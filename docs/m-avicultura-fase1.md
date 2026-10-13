# Capacidad e instalaciones avícolas — fase 1

Acceso: Grandes especies / Producción → Cálculos clínicos → Aves · Capacidad e instalaciones. Módulo Flutter `lib/modules/aviculture`, sin tablas Supabase nuevas. Funciona con parámetros locales; no escribe expedientes, lotes o tratamientos.

Datos recibidos en el mensaje del 13 de octubre de 2026: 12 filas de capacidad/longitud y 7 de equipos, conservados como CSV versionados en `assets/clinical/aviculture/`. Se reconstruyeron los encabezados mezclados del mensaje según las columnas de cada tabla, sin agregar cantidades. Fuentes y estados originales `sin_verificar` preservados. Incubación (tres valores) se conserva como referencia adicional en JSON; no se usa para calcular superficie/equipos.

Tres parámetros pendientes: comedero de tolva, temperatura por edad y presión de agua. Valores/unidades/fuentes null. Minitolva no se sustituye por tolva convencional. No se crean temperaturas, presiones ni densidades nuevas.

Etapas 0–6, 7–12 y 13+ semanas y sistemas piso/jaula seleccionables. La semana final vacía de postura se conserva; no se fija edad máxima. Cada parámetro tiene rango, fuente y estado visibles, sin valor de diseño preseleccionado. Fuera del rango se avisa, conservando la posibilidad de una simulación explícita; nunca equivale a aprobación técnica.

Capacidad: largo/ancho útiles de una superficie, cm o m; pisos por módulo, módulos por caseta, casetas iguales. En piso exige una superficie por módulo. Capacidad se redondea abajo por superficie independiente y después se multiplica; no agrupa sobrantes de jaulas. No representa volumen, ventilación o certificación de bienestar.

Equipo: aves → área, longitudes de comedero/bebedero y equipos individualmente con su valor de aves/unidad. Los apuntes de equipos usan etapas distintas (inicio, primeros 8–12 días, crianza, crianza/postura); se presentan para elección expresa y no se reinterpretan como desarrollo o se extrapolan automáticamente. Notas de capacidad kg/L y BTU/h se muestran, sin calcular consumos adicionales.

Cálculos puros con racionales BigInt. Conversión 10 000 cm²/m²: aves/m² ↔ cm²/ave. Equipos redondeados arriba a entero. Metros y área redondeados arriba a incremento indicado por el usuario; no se inventa una precisión de compra. Resultados redondeados se muestran hasta nueve decimales para respetar incrementos admitidos. Valores intermedios aproximados son solo presentación; decisiones exactas. El usuario debe medir la longitud accesible; no se duplican automáticamente los lados de un comedero.

Al cambiar entradas o selección se invalidan resultados. Se muestra procedimiento y avisos. Datos sin verificar permitidos para simulación geométrica, con advertencia visible; no se adoptan como recomendación de manejo ni se conectan a dosis.

Pruebas: capacidades 4/3 aves en 1000 cm² a 250/300 cm², superficies independientes, 1000/1001 aves por niple de 10, redondeo de metros, conversiones y validación de enteros/ceros, rangos y carga real de assets sin parámetros inventados; interfaz sin diseño preseleccionado. Instalación Android con este módulo aún pendiente de nuevo APK.

Fase 2 no implementada: redistribución de lote con déficit; vínculo de lote con medicación en agua/alimento; retiro del huevo en registro de tratamientos. Requiere modelo de lotes, referencias verificadas y preservación de historia; no se inventan tiempos de retiro ni se reutilizan automáticamente retiros de carne/leche.

Verificación del 13 de octubre de 2026: análisis Flutter sin incidencias; 159 pruebas de la suite general pasaron (se excluyó solo el caso criptográfico lento, ajeno a este cambio). Módulo con repositorio de assets, ViewModel y motor puro; no se desplegaron cambios de esquema Supabase.
