# VetDosis — reconciliación documental de catálogo PDF 1/10: HALVET

**Fecha:** 2026-10-22. **Fuente:** `568390004-Catalogo-Halvet.pdf`, 24 páginas, aportado por la usuaria.
**SHA-256:** `44e0081229e9f3a0356fe9c7c51fb62052af924a4aea68509d4f8901263af317`.
El PDF original se conserva como adjunto en el chat de origen; no se ha subido a GitHub/Storage. El archivo local `VetDosis_Halvet_PDF1_catalogo_completo_y_cruce_20261022.json` contiene los 72 nombres del índice (página PDF 3), enlaces PLM candidatos y texto recuperado de las 24 páginas; **esta transcripción textual contiene caracteres dañados** y requiere cotejo visual.

## Conciliación comprobada contra el catálogo de 1,384 productos PLM

| Resultado | Entradas |
|---|---:|
| Entradas en índice PDF de HALVET | 72 |
| Coincidencias directas por nombre normalizado + fabricante | 57 |
| Nombres alternativos / posibles alias sin validar | 11 |
| Candidatos presentes en PDF pero no identificados en PLM | 4 |
| Entradas PDF con páginas candidatas del cuerpo localizadas | 69 |
| Formulaciones PDF-solo cuya ficha técnica se comprobó visualmente | 3 |

**Candidatos PDF-solo:** GENTALEN, GENTALEN 50, ORTOFEN, LEVANTON. **ORTOFEN solo consta en el índice**: no se localizó su ficha individual, así que NO tiene dosis ni concentración añadidas. GENTALEN 20 mg/mL, GENTALEN 50 mg/mL y LEVANTON 12 g de levamisol HCl/100 mL tienen fichas en páginas PDF 22–23 y se guardaron como **hechos del documento en revisión privada**. Dosis, advertencias, presentaciones y registro se conservan de manera separada por formulación.

**Posibles alias** (no fusionar sin cotejar): BENDAVAL PLUS TABLETAS → BENDAVAL PLUS; DICLOFEN HALVET → DICLOFEN; ENROL CON DIPIRONA TABLETAS → ENROL TABLETAS; LIMPER → LIMPER SHAMPOO; NEUTRAC → NEUTRAC ORAL; RESPAIRE → RESPAIRE TABLETAS; RESULVET → RESULVET TABLETAS; ANABEN PESO PESADO → ANABEN 4 PESO PESADO; BRAVO BIG SPRAY → BRAVO SPRAY BIG; ENROL CON DIPIRONA SOLUCIÓN → ENROL CON DIPIRONA; VIRUSTAD HALVET → VIRUSTAD.

## Qué se cambió en Supabase Pruebas

- Migración aditiva `15G_manufacturer_pdf_catalog_crosswalk.sql`: tablas privadas `manufacturer_pdf_sources`, `manufacturer_pdf_product_index` con 72 entradas y sugerencias de enlace a PLM.
- `pdf_page_candidates`: 69 registros con páginas candidatas identificadas (3 faltantes).
- Migración `15H_halvet_pdf_facts_and_canonical_preview.sql`: columna JSONB `document_facts` por entrada PDF, y vista de revisión `commercial_catalog_review_preview` en esquema privado `vetdosis_reference_staging`. La vista muestra **1,388 registros** de revisión: 1,384 productos PLM + 4 candidatos PDF-solo, sin duplicar de nuevo los 68 registros PDF ya vinculados de forma exacta o tentativa.
- Los **1,384 registros PLM siguen intactos**. No se borró nada.
- Tres registros PDF-solo tienen hechos técnicos comprobados visualmente en el PDF (`detail_checked`, **no** aprobación clínica).
- RLS en tablas fuente; sin privilegios de lectura para `anon` ni `authenticated`.

## Regla de combinación

No usar `DELETE` sobre productos PLM. Las coincidencias se manejan como referencias documentales adicionales, preservando versiones de laboratorio, unidad y forma farmacéutica. La vista de revisión ya omite la duplicación literal de las 68 entradas del PDF que tienen correspondencias/candidatos PLM, pero **no consolida las posibles equivalencias como hechos aprobados**. Si se confirma una equivalencia, mostrar en el futuro una ficha combinada con procedencia PLM + PDF, priorizando composición y posología de fabricante vigente por **formulación exacta**.

## Trabajo pendiente en este mismo PDF

1. Revisar manualmente los 11 alias posibles; especial cuidado con formulaciones que comparten nombre pero cambian de vía o concentración.
2. Completar los campos de dosis, contraindicaciones, retiro, especies y presentación **de las 72 entradas**; de momento este paso solo comenzó con 3 fichas PDF-solo y cinco fichas originales previamente cotejadas por separado (MELODEX/METRONID/PREGABALYN de otros PDFs). Haber indexado una entrada NO significa haber incorporado su ficha técnica completa.
3. Revisar los encabezados que no se localizaron por extracción textual: ENROL CON DIPIRONA TABLETAS, ESCUDERM TABLETAS y ORTOFEN (esta última sin ficha individual localizada).
4. Solo después, contrastar vigencia/etiqueta con fabricante, promover evidencia aprobada y preparar integraciones al Vademécum Comercial por las reglas correctas. No activar dosis sin revisión clínica.

## Consultas

```sql
select reconciliation_status,count(*) as n
from vetdosis_reference_staging.manufacturer_pdf_product_index
group by 1;
select * from vetdosis_reference_staging.commercial_catalog_review_preview;
```
