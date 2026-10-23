# VetDosis — Halvet: ficha técnica, páginas PDF 4 y 5

**Fuente**: archivo aportado por la usuaria `568390004-Catalogo-Halvet.pdf`, 24 páginas. **SHA-256** `44e0081229e9f3a0356fe9c7c51fb62052af924a4aea68509d4f8901263af317`. **Fecha de cotejo documental**: 22 de octubre de 2026. Cada página PDF 4/5 lleva número impreso 1/2. Extracción combinada: texto seleccionable más inspección visual de páginas originales. **No es validación clínica ni etiqueta vigente verificada**.

## Productos inspeccionados

| Entrada PDF | Nombre | Activos/formulación declarados | Pauta resumida de fabricante | Avisos |
|---:|---|---|---|---|
| 1 | ANIMOX SUSPENSIÓN | Amoxicilina base 0.5 g/8 g de polvo, reconstituir con 15 mL, Q-6642-052 | Caninos/felinos 0.6 mL/kg, fuente equivale a 20 mg/kg | Intervalo no especificado; conservar mezcla refrigerada hasta 10 días |
| 2 | ANIMOX TABLETAS | Amoxicilina 150 mg/tableta, caja 30, Q-6642-036 | 1 tableta/10 kg en cantidad **total diaria**, dividible en dos tomas cada 12 h según ficha | No inferir que está permitido partir la tableta físicamente |
| 3 | BENDAVAL GOTAS | Albendazol 50 mg/mL, frasco 18 mL, Q-6642-043 | Caninos 0.6 mL/kg (varios esquemas por indicación), felinos 0.5 mL/kg cada 12 h por 2–3 días según indicación | Encabezado 30 mg/kg vs pauta de felinos equivalente a 25 mg/kg; Dipylidium menciona 3 días y 3 aplicaciones, inconsistente |
| 4 | BENDAVAL TABLETAS | Albendazol 300 mg/tableta, caja 30, Q-6642-016 | 1–2 tabletas/10 kg con duración distinta según nematodos/cestodos/protozoarios | No confundir las pautas ni presumir divisibilidad física |
| 5 | BENDAVAL PLUS TABLETAS (PDF) / BENDAVAL PLUS (PLM) | Por tableta: albendazol 300 mg + praziquantel 50 mg + pamoato de pirantel 150 mg, caja 30, Q-6642-091 | 1 tableta/10 kg, toma única | Menores de 4 semanas caninos, menores de 6 semanas felinos y primer tercio de gestación: restricciones de ficha; alias confirmado como candidato por composición, nombre conservado |
| 6 | BENDAVAL PLUS SUSPENSIÓN | Por mL: albendazol 50 mg + praziquantel 10 mg, frasco 100 mL, Q-6642-093 | Ovinos/caprinos/porcinos 1 mL/5 kg; caninos/felinos 1 mL/kg; ambos cada 12 h por 5 días según ficha | Retiro de 21 días; no hembras productoras de leche para consumo |
| 7 | BRAVO JABÓN | Permetrina declarada 1 % (0.8 g/80 g), jabón 80 g, Q-6642-103 | Aplicación tópica suficiente, mínimo cinco minutos antes de enjuague | **No usar en felinos**; no en menores de tres meses ni hembras gestantes; no es dosificación por kg |
| 8 | BRAVO SHAMPOO | Texto del fabricante: permetrina **1 % (2.7 g/100 mL)**, registro RSCO-PEC-INAC-0156-310-340-001 | 20 mL por aplicación tópica, dejar cinco minutos, repetir cada 10–14 días según ficha | **Inconsistencia de concentración** que exige revisión; no generar dosis por kg |

## Cambios remotos comprobados

1. Los ocho productos p.4–5 se enlazan a sus fichas PLM originales, se conservan formulaciones separadas y se registran datos del fabricante en `manufacturer_pdf_product_index.document_facts`. Para dosificar no basta con que compartan marca.
2. `commercial_product_enrichment` registra las ocho fichas con fuente PDF, página y hash. **No se cambió ni borró** ninguno de los 1,384 productos PLM originales.
3. La tarea programada había registrado algunas pautas de estas mismas páginas anteriormente. La migración `15I_commercial_label_regimen_dedup.sql` añade `duplicate_of_regimen_key` y una vista privada `commercial_label_regimens_reconciled`; **diez pautas redundantes se vincularon a las canónicas sin borrar evidencia**. Cotejo final: 58 registros históricos de pautas en total, 48 filas en la vista reconciliada, 16 pautas no redundantes relacionadas con estos ocho productos (incluye resumen por indicaciones).
4. A la hora del cotejo remoto, **37/1384** productos estaban revisados individualmente y **1347** permanecían en `index_only`.
5. Las tablas permanecen privadas, con RLS y SELECT denegado para roles `anon` y `authenticated`. Ninguna posología fue promovida al motor farmacológico ni a prescripción automática.

## Pendientes

- Revisar que todos los esquemas de BENDAVAL sean consistentes para parásito, especie, intervalo y duración; hay contradicciones literales.
- Contrastar el **1 % vs 2.7 g/100 mL** de BRAVO SHAMPOO contra una etiqueta vigente del laboratorio.
- Verificar que las tabletas permitan realmente fraccionamiento antes de mostrar medios/cuartos; el cálculo de partes es distinto de autorización física.
- Continuar Halvet desde el índice PDF 9 en adelante, sin reiniciar el inventario ya guardado.
- **No publicar texto completo ni fotografías de estos catálogos.** Mantener referencias a fuente PDF y página, dosis transcritas en forma resumida y estado de revisión.

## Artefacto local

`VetDosis_Halvet_p04-p05_8_fichas_revision_20261022.json` — ocho fichas de revisión en JSON resumido, vinculadas al PDF fuente y cada página, sin imágenes ni documentos editoriales completos.
