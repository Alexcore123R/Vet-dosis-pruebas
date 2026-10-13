# Incubación de gallinas: calculadoras y referencias

Acceso: Grandes especies / Producción → Cálculos clínicos → Aves · Incubación. Módulo MVVM con repositorio de assets, ViewModel y motor racional puro. Referencias en `assets/clinical/incubation/referencias.v1.json`, copiadas de la investigación documental sin alterar su aprobación: todas sin verificar, no preseleccionadas como parámetros operativos.

## Alcance implementado

1. Peso del pollito: peso del huevo × porcentaje de rendimiento elegido. No valor universal 70%. Fuentes Hy-Line/NOVOGEN visibles con contexto y enlaces; porcentaje se captura expresamente.
2. Pérdida: mismo huevo o muestra comparable, pesos netos inicial/actual y día. Se confirma ausencia de tara/comparabilidad/corrección de huevos retirados. Fórmula (inicial−actual)/inicial×100. Si aumenta el peso, conserva porcentaje negativo y pide revisar medición/comparabilidad. La curva de clase conserva solo días 3/6/9/12/15/18; día distinto devuelve pérdida observada sin interpolación. En día documentado muestra peso esperado y diferencia en puntos porcentuales, no cambio automático de humedad.
3. Dilución: producto/presentación y fuente capturados, concentración inicial y objetivo del mismo activo, volumen final en ml y confirmación del prospecto. Convierte únicamente mg/ml, mg/L y % m/v; permite entrada ppm solo cuando se declara equivalencia mg/L documentada, nunca ppm genérica. Rechaza %m/m/%v/v/ppm sin base, ceros y objetivo superior a inicial. C₁V₁=C₂Vfinal; muestra producto y diferencia volumétrica teórica, completando hasta volumen final. No redondea una preparación ni garantiza estabilidad/compatibilidad. No calcula polvos, mezclas de varios productos ni fumigación por m³.

Cada cambio invalida el resultado; datos/unidades de dilución invalidan también la confirmación. Resultados de visualización aproximados a nueve decimales; decisiones aritméticas usan racionales exactos. No son indicaciones terapéuticas ni autorización de desinfectar huevos.

## Fuentes y datos pendientes

Vista de consulta de los 17 parámetros con rangos, contexto, fuente y enlaces. No se mezclan aire/cáscara, incubadora/nacedora, multietapa/monoetapa o tiempos desde encendido/edad embrionaria. Dos productos se muestran como candidatos de investigación, sin rellenar una dilución a partir de ellos. La discrepancia 35 °C vs 99,5–100 °F queda visible. No se cargó una curva diaria nueva ni se duplicaron los parámetros de volteo del módulo de instalaciones.

Pendientes: perfil operativo por línea y máquina, revisión docente/MVZ, fichas comerciales vigentes con bases inequívocas, registro histórico de pesajes por lote, gráficos de seguimiento, alertas ambientales y conexión con sensores. No escribe Supabase, no controla equipos, no crea tratamientos ni retiros del huevo. Fase 2 de instalaciones avícolas sigue pendiente.

Verificación: pruebas de 65 g al 70% =45,5 g y al 66% =42,9 g, pérdida 10%, referencia de día 18, peso aumentado, días no documentados, conversiones y bases bloqueadas, dilución ficticia, falta de fuente/confirmación, invalidación y carga de assets sin valores preseleccionados. Las 27 pruebas de incubación, capacidad avícola y cálculos previos pasaron. Nuevo APK todavía pendiente.
