# VetDosis — ingreso bibliográfico sin publicar datos clínicos

Fecha: 22 de octubre de 2026. Esta rama se basa en PR #10 y extiende `15A_reference_staging.sql` con `15B_reference_raw_intake.sql`.

**Objetivo:** conservar la transcripción completa de 1,087 filas procedentes de dos libros de auditoría: lotes 1–7 (582) y lote 8 Qwen (505). La auditoría contiene campos ausentes o ambiguos: no se fuerzan a `candidates` ni se inventan valores; todas las filas se importan como `pending` en `raw_intake_rows`.

**Fuentes:** `VetDosis_auditoria_consolidada_lotes_1_a_7.xlsx` (hoja «Indice registros») y `VetDosis_lote8_auditoria_laboratorio_constantes_20261021.xlsx` (hoja «Qwen 505»). Cada fila guarda el payload entero, su libro, hoja, número de fila, digest SHA-256 y clave idempotente. Los 166 exóticos complementarios del segundo libro ya se encuentran representados en los lotes anteriores y no se duplicaron.

**Plan real:** ejecutar `15A` y `15B` solo después de confirmar el estado actual del proyecto de pruebas, verificar un respaldo y revisar DDL. Luego importar por lotes con los ficheros SQL preparados a partir de las planillas (80 registros por archivo), haciendo conteo/digest después de cada paso. Los SQL preservan datos originales y no ejecutan el SQL bruto de Qwen (contiene `DROP TABLE CASCADE`). No ejecutar ningún script en producción, no abrir Data API al nuevo esquema y no conectar referencias pendientes a dosis/calculadora.

**Separación de ambientes:** la persona usuaria quiere cargar tablas para revisión de Johana (MVZ) y colegas. Esta migración NO crea acceso de revisión desde la app. El acceso controlado por MVZ se diseñará después, con estados independientes, atribución, bitácora y sin promoción automática.

**Estado de la implementación en esta PR:** estructura nueva y pruebas sintéticas preparadas. Ninguna escritura ejecutada en Supabase remoto y no se afirma que el servidor ya disponga de 15A. Los archivos completos de importación viven en el paquete descargable de esta conversación (no están incorporados al GitHub privado); deben transferirse a un entorno autorizado para ejecutar. Los minutos de GitHub Actions están agotados.

**Pruebas necesarias:** `bash supabase/tests/run_reference_raw_intake.sh` con Docker/PostgreSQL 17 y SQL de prueba sintético. Para validar la importación real, ejecutar el SELECT de conteos por lote y confirmar 582 + 505 filas pendientes, usando exclusivamente la base de pruebas y la identidad administrativa autorizada.


## Alta efectiva del catálogo comercial — Supabase Pruebas (22-oct-2026)

Se aplicaron las migraciones aditivas `15A_reference_staging.sql`, `15B_reference_raw_intake.sql` y `15C_commercial_products_intake.sql` en el proyecto de **Pruebas** `wtrelwtztkddfktrfdpb`. Esta sección documenta únicamente el catálogo PLM/PEV: **NO** los 1,087 registros bibliográficos.

- Tabla: `vetdosis_reference_staging.commercial_products_intake`.
- Estado remoto comprobado por `SELECT COUNT(*)`: **1,384** filas, **1,384** enlaces distintos; 0 productos sin nombre; 0 discrepancias entre URL de columna y URL en `original_payload`.
- Huella de integridad: MD5 de `string_agg(product_url || '|' || product_name, E'\\n' ORDER BY product_url COLLATE "C")`: `c0919b11987a7dc913a7b99878fc56e5`, igual a la calculada sobre los 1,384 objetos del archivo de usuario `VetDosis_PLM_27_de_27_productos_para_revision.json`. Esta huella sirve para cotejo de transferencia, no para verificar la exactitud de las fichas frente a los laboratorios.
- Todas las filas siguen en `pending_source_review`; se conservaron nombres comerciales, presentaciones, sustancias sin normalizar, fabricantes, resúmenes, URLs, archivos fuente, letra e información JSON original. La clave única es `product_url`, por lo que la carga es idempotente.
- **Aislamiento verificado:** RLS habilitada; roles `anon` y `authenticated` sin `SELECT` y sin `USAGE` del esquema privado.
- **No se modificaron** las tablas productivas `public."Fármacos"`, `public."Fármacos personalizados"`, recetas, pacientes o calculadoras. No se habilitó publicación en la aplicación ni se normalizaron dosis.
- Los **1,087** registros de los lotes bibliográficos/fisiología/laboratorio **siguen pendientes de importación** a `raw_intake_rows`; su paquete y su comprobación son un trabajo distinto.
- La propietaria aportó los HTML como índice de fichas publicadas de fabricantes. La clasificación legal de cada elemento y las condiciones de redistribución del directorio deben verificarse antes de exponer cualquier material en un producto público; la copia actual es una bandeja privada de revisión.
- No existía respaldo automático restaurable verificado en la cuenta gratuita; la operación fue aditiva hacia tabla nueva, conservando sin cambios las tablas y datos previos. Conservar fuera de Supabase el JSON original y su manifiesto hasta concluir la revisión.
