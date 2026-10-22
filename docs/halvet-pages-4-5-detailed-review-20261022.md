# VetDosis — HALVET, fichas técnicas PDF páginas 4–5

Fecha: 22/10/2026. Fuente: **568390004-Catalogo-Halvet.pdf** (24 páginas; p.4–5 del PDF equivalen a páginas impresas 1–2). Hash SHA-256:
`44e0081229e9f3a0356fe9c7c51fb62052af924a4aea68509d4f8901263af317`.

Este documento registra **hechos transcritos del catálogo aportado por la usuaria**, cotejados visualmente con las páginas. No implica aval clínico, vigencia regulatoria, derecho de republicación del PDF completo ni autorización para generar prescripciones automáticas.

## Registros cotejados visualmente

| Producto | Página PDF | Formulación | Registro impreso | Estado |
| --- | ---: | --- | --- | --- |
| ANIMOX SUSPENSIÓN | 4 | Amoxicilina base 0.5 g por 8 g de polvo reconstituible | Q-6642-052 | PDF y PLM por mismo nombre |
| ANIMOX TABLETAS | 4 | Amoxicilina base 150 mg/tableta | Q-6642-036 | PDF y PLM por mismo nombre |
| BENDAVAL GOTAS | 4 | Albendazol 50 mg/mL | Q-6642-043 | PDF y PLM por mismo nombre |
| BENDAVAL TABLETAS | 4 | Albendazol 300 mg/tableta | Q-6642-016 | PDF y PLM por mismo nombre |
| BENDAVAL PLUS TABLETAS | 5 | Albendazol 300 mg + praziquantel 50 mg + pamoato de pirantel 150 mg por tableta | Q-6642-091 | **Posible alias** de BENDAVAL PLUS en PLM; pendiente confirmar |
| BENDAVAL PLUS SUSPENSIÓN | 5 | Albendazol 50 mg/mL + praziquantel 10 mg/mL | Q-6642-093 | PDF y PLM por mismo nombre |
| BRAVO JABÓN | 5 | Permetrina 1 %; barra de 80 g | Q-6642-103 | PDF y PLM por mismo nombre; **no dosificable por kg** |

## Pautas y alertas a conservar

- **ANIMOX suspensión:** el documento declara 0.6 mL/kg (equivalente indicado 20 mg/kg), pero la frecuencia no está definida en ese párrafo. No inventar frecuencia ni concentración final a partir de la reconstitución.
- **ANIMOX tabletas:** el texto propone 1 tableta/10 kg cada 24 horas o dividir la dosis total en dos tomas cada 12 horas. Esto **no prueba** que las tabletas puedan cortarse en mitades físicamente; corroborar etiqueta/ranurado.
- **BENDAVAL GOTAS:** indicaciones y duraciones varían por especie y parásito. **Conflicto:** para Dipylidium la ficha pone “cada 12 h durante 3 días” pero agrega “3 aplicaciones”; podrían ser seis si se siguiera estrictamente el intervalo. Bloqueado en `conflict_needs_resolution`.
- **BENDAVAL TABLETAS:** la ficha distingue tratamientos según helmintos/cestodos/protozoos y distintos números de administraciones. No convertir la descripción en una única regla lineal.
- **BENDAVAL PLUS TABLETAS:** etiqueta expresa 1 tableta/10 kg en toma única; la correspondencia con el nombre más corto en PLM aún es **candidata**, por lo que la dosis permanece por ahora únicamente ligada a la entrada documental PDF, sin inserción por alias no confirmado.
- **BENDAVAL PLUS SUSPENSIÓN:** en animales de producción indica 1 mL/5 kg cada 12 horas durante 5 días; para caninos/felinos indica 1 mL/kg cada 12 horas durante 5 días. La fuente registra retiro de 21 días y restricción en hembras productoras de leche para consumo.
- **BRAVO JABÓN:** indicaciones tópicas por modo de empleo; explícitamente **no** extrapolar por peso. El fabricante advierte no usar en felinos y otras restricciones de edad/gestación.

## Cambios realizados

1. `manufacturer_pdf_product_index`: 7 nuevas filas con `verification_state=detail_checked` y `document_facts` estructurado (producto, composición, presentación, especie, vía, pauta resumida, alertas, registro y página).
2. `commercial_label_regimens`: 11 pautas adicionales **en staging privado**, vinculadas solo a los seis productos con enlace PLM exacto; la variante de nombre pendiente no se fusionó.
3. `commercial_product_enrichment`: seis productos exactos se marcaron con consulta documental `manufacturer_checked`; se preservó el catálogo PLM original.
4. El archivo fuente se conserva entre los adjuntos originales; solo se almacenan en el esquema de revisión referencias al documento (nombre, hash y página) y resúmenes factuales. `medical_review_state=not_reviewed` y `auto_dosing_enabled=false`.

## Qué sigue

Verificar visualmente páginas 5–7 restantes del apartado de animales de compañía, completar BRAVO SHAMPOO y CARPROTEC/otras formulaciones del siguiente bloque; cotejar aliases solamente con coincidencia exacta de ingredientes y concentración, antes de deduplicar en la vista clínica. No borrar referencias de origen.

La captura documental precede a toda revisión MVZ, confirmación de etiquetas vigentes y habilitación de cálculos comerciales.
