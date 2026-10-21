# VetDosis — zona de preparación de referencias (propuesta 15A)

## Motivo
Los lotes bibliográficos 1–8 y el SQL original de Qwen incluyen datos heterogéneos, duplicados, rangos contradictorios, unidades dudosas y fuentes de calidad variable. No deben alimentar automáticamente las calculadoras de dosis ni los intervalos de laboratorio. El SQL de Qwen incluye `DROP TABLE ... CASCADE`; **no ejecutarlo** en el proyecto Supabase.

## Separación de responsabilidades
- `vetdosis_reference_staging.sources`: obra, edición, atribución y procedencia.
- `vetdosis_reference_staging.import_batches`: lote y huella SHA-256 del archivo original, cuando esté disponible.
- `vetdosis_reference_staging.candidates`: una transcripción por fila, con texto original, especie literal, página/sección, unidad literal, método/contexto, valores numéricos opcionales y estado de revisión.
- Un `batch_key + row_key` repetido se rechaza para evitar duplicar accidentalmente la misma fila al reimportar. Dos fuentes distintas **pueden** mantener intervalos diferentes.
- `interval`, `point`, `upper_bound`, `lower_bound` y `unparsed` se distinguen expresamente, sin convertir puntos en rangos ni `NULL` en cero.
- El estado de revisión en staging solo admite `pending`, `conflict` y `rejected`. La **aprobación clínica no puede ocurrir en estas tablas**.

## Límite de seguridad
Es un esquema separado, sin políticas RLS de lectura y sin grants a clientes. No se expone por ninguna vista, RPC ni API de la app; no modifica el catálogo local de `mg/kg` / `mg/ml` ni `clinical_vital_sets.reference_snapshot`. Una futura publicación de referencias aprobadas necesita un flujo separado con identidad y fecha de la persona revisora, auditoría y controles regulatorios.

## Secuencia propuesta de importación
1. Preservar originales (PDF, CSV, SQL) y registrar SHA-256 cuando sea posible.
2. Crear un `source_key` por edición o recurso exacto; si la fuente no está identificada, dejarlo explícito como material no identificado.
3. Producir un `row_key` determinista por lote, sin borrar/reescribir referencias previas.
4. Insertar en staging como `pending`; los conflictos conocidos deben ingresar como `conflict`.
5. Auditar unidades y método, especie taxonómica, población y discrepancias entre fuentes.
6. Diseñar **en otra PR** un catálogo clínico versionado, permisos de aprobación, bitácora y pruebas. No publicar valores sin una decisión explícita de revisión.

## Validaciones
Ejecutar `bash supabase/tests/run_reference_staging.sh` en máquina con Docker. Usa PostgreSQL 17 en contenedor sin red, ejecuta la definición dos veces para comprobar repetibilidad y valida rechazo de duplicados, intervalos invertidos, estado aprobado y acceso de un rol cliente sintético.

**Estado**: propuesta no desplegada; aún no se han cargado los 505 registros de Qwen ni los lotes 1–8.
