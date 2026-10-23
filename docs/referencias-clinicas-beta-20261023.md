# Referencias fisiológicas y de laboratorio para evaluación cerrada

El proyecto de pruebas conserva 1.087 filas RAW en `vetdosis_reference_staging.raw_intake_rows`. La biblioteca de la app presenta 301 transcripciones fisiológicas (166 del índice bibliográfico y 135 del lote 8), 370 de laboratorio y dos propuestas de temperatura rectal contrastadas con Merck. Todas las transcripciones siguen pendientes; ninguna modifica el catálogo de cálculo, interpreta resultados de pacientes o emite recetas.

La consulta `reference_review_list` solo entrega estas referencias a integrantes admin/MVZ de la clínica con `clinical.read` vigente. El esquema RAW sigue fuera de lectura directa de `anon` y `authenticated`. La pantalla enseña fuente, hoja, fila, notas y alternativas del mismo parámetro y unidad, con búsqueda y paginación.

## Resolución documentada

El lote 8 dice perro 37,5–38,5 °C y gato 38–39 °C, atribuidos de forma conjunta a «Slideshare / Merck Vet Manual». La tabla específica del [Merck Veterinary Manual](https://www.merckvetmanual.com/multimedia/table/normal-rectal-temperature-ranges), consultada el 23 de octubre de 2026, da perro 37,5–39,2 °C y gato 38,1–39,2 °C. La app destaca esos intervalos como **fuente externa contrastada, pendiente de revisión MVZ** y conserva los rangos del lote como alternativas; no los activa en la clasificación automática de constantes.

En el lote 8 hay 27 combinaciones de especie, parámetro y unidad con más de un intervalo de laboratorio. No se elige un único intervalo general: [Cornell Animal Health Diagnostic Center](https://www.vet.cornell.edu/animal-health-diagnostic-center/laboratories/clinical-pathology/reference-intervals) publica intervalos por especie y método; su [química Cobas](https://www.vet.cornell.edu/animal-health-diagnostic-center/laboratories/clinical-pathology/reference-intervals/chemistry-cobas) señala diferencias según muestra. [eClinpath](https://eclinpath.com/test-basics/reference-intervals/) explica que analizador, método y reactivo afectan la validez. Antes de seleccionar un rango para interpretar un resultado real se necesita el laboratorio emisor, método/analizador, muestra y condiciones de la población. La pantalla muestra las alternativas y pide esa revisión.

La biblioteca es de consulta para evaluadores de la beta cerrada. La aprobación clínica de cada entrada, la comprobación de la fuente original y el vínculo con rangos automáticos requieren una revisión MVZ atribuida y versionada.
