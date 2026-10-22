# VetDosis — lote de 10 vademécums aportados por la propietaria

**Fecha de registro:** 2026-10-22. **Ámbito:** trabajo privado de investigación, no publicación de contenido integral. Los PDFs originales están adjuntos en el chat de origen, no se han copiado a GitHub ni a Storage.

**Trazabilidad:** cada archivo posee SHA-256 y número de páginas; para encontrar una declaración, cotejar hash + página con el PDF original. Hay dos documentos escaneados, para los que falla la búsqueda de texto y debe consultarse la imagen. La ausencia de una coincidencia de texto NO demuestra la ausencia del producto.

| PDF | Págs. | Texto | SHA-256 | Hallazgo |
|---|---:|---|---|---|
| 03-MederiLab-Vademecum.pdf.pdf | 40 | escaneado | `23cb2baf010ccc7d52cb5ea0a824813f4019796166160594db852e6bec4eaa73` | PREGABALYN-5, -10, -30: p.14 |
| VADEMECUM-VIRBAC.pdf | 75 | texto | `12861c7dc4c1f710d9359b350f4498ea4b0709d1bc0bfc01771a3945ba6f2669` | catálogo de animales de producción |
| Prontuario_Veterinaria_2026.pdf | 26 | escaneado | `ac2ccb6f5e8abd0ddebb62e7c3d307fbb0dc7c0730e1448a605d84ddbf3a15da` | revisión visual pendiente |
| Catálogo Innopharma.pdf | 20 | texto | `e45e002554f304622e829c8d12a90b16b8c0680448b4f221f7430302c904dce6` | varios productos propios; p.16 ejemplo de antiparasitario |
| GUIA_DIGITAL_VETS_PHARMA_2022_compressed.pdf | 36 | texto | `9ede5cdc78b6d9cfa17ce4a5b7c8e58900b2cc5ac90fc14d09d21b43f4091d6b` | animales de producción; fuente 2022 |
| vademecum-de-bolsillo-espanol.pdf | 238 | texto | `e891e5c013d17654d608e646f0e9e979b56234ca3f56e1f1e2eaa9680c68459a` | vademécum general: no atribuir como fabricante sin verificar |
| vademecum-concodigos-2026_05_06-11_39_03-compressed.pdf | 27 | texto | `d1bf419a0a5b03692e62e759a7d94288ae9aeea29082e96ccf79db3ebe49a1d8` | laboratorios Andoci |
| vademecum_esp.pdf | 32 | texto | `d44d70be338ee5ffca9031cdade832b561e8d093e8d3bd52db3c0cd50dc33361` | Riverfarma |
| Catalogo_APETS24_Small.pdf | 20 | texto | `03d9c66168ec340ed8660fb77db149d0a4b4d2875eed4e9548e768e799a2be0b` | MELODEX TABS: p.12 |
| 568390004-Catalogo-Halvet.pdf | 24 | texto | `44e0081229e9f3a0356fe9c7c51fb62052af924a4aea68509d4f8901263af317` | METRONID: p.9 |

## Hallazgos de la tanda original de 10 productos

La lista pedida originalmente tenía 10 presentaciones (MELODEX TABS, METRONID, NEXGARD, NEXGARD SPECTRA, PARASTIN BIG DOG, PARASTIN DOG, PARASTIN DOGGY, PREGABALYN-5, -10, -30). Estos archivos han permitido documentar **cinco** mediante fuente original:

- **MELODEX TABS**: Aranda Pets PDF, p.12. Meloxicam 2 mg/tableta, 30 tabletas, Q-0449-278, oral, canino: inicio 1 tableta/10 kg, mantenimiento 1/2 tableta/10 kg; felino: 1/4 tableta/5 kg; cada 24 h, máx. 10 días según texto del catálogo. Fracciones indicadas en la pauta del catálogo, sin confirmación de ranura o si el comprimido puede partirse de forma exacta. Particular atención a restricciones de AINE y felinos; no habilitado como recomendación clínica.
- **METRONID**: Halvet PDF, p.9. Metronidazol 250 mg/tableta, 30 tabletas, registro Q-6642-050, uso en caninos y felinos, oral. Texto: 25 mg/kg (1 tableta/10 kg) y recomendación de **repartir el total en tres tomas diarias** durante 5–7 días; se clasificó como `label_complex`, no por toma individual, por interpretación pendiente de revisión.
- **PREGABALYN-5**: Mederi PDF escaneado p.14. Pregabalina 10 mg/tableta, caja de 30, registro Q-1190-049; caninos: 1 tableta/5 kg cada 8–12 h. Aumento gradual hasta 4 mg/kg solo a criterio MVZ; receta cuantificada.
- **PREGABALYN-10**: Mederi p.14. Pregabalina 20 mg/tableta, caja de 30, Q-1190-050; caninos: 1 tableta/10 kg cada 8–12 h, mismos requisitos.
- **PREGABALYN-30**: Mederi p.14. Pregabalina 60 mg/tableta, caja de 30, Q-1190-091; caninos: 1 tableta/30 kg cada 8–12 h, mismos requisitos.

Las otras cinco de esa tanda **no se han cotejado todavía** con estas fuentes: NEXGARD, NEXGARD SPECTRA, PARASTIN BIG DOG, PARASTIN DOG y PARASTIN DOGGY. No significa que estén ausentes de todos los PDF; solo que no se encontró una fuente cotejada con dosis individual en el análisis inicial.

## Inserción privada realizada

- `commercial_product_enrichment`: 5 filas con datos de composición, presentaciones, especies, vía, registro, PDF de origen, página y hash; `medical_review_state = not_reviewed`.
- `commercial_label_regimens`: 7 pautas de fabricante como `manufacturer_document` (3 PREGABALYN, 3 MELODEX, 1 METRONID). No habilitadas al motor de dosis ni prescripción.
- No se ha realizado copia en Storage ni OCR de 10 PDFs completos.
- **Siguiente actividad**: investigar más coincidencias en los catálogos; validar físicamente partición de tabletas, contraindicaciones, versión actual de ficha y pauta completa, sin promover registros a uso clínico.

> Los intervalos y cantidades aquí son transcripciones documentales, no sustituyen la indicación de un MVZ ni la etiqueta vigente.
