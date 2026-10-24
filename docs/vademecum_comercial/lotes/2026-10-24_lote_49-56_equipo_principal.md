# VetDosis — revisión documental comercial, lote 49–56
**Fecha de consulta:** 2026-10-24. **Proyecto:** Supabase Pruebas (`wtrelwtztkddfktrfdpb`). **Tablas privadas:** `vetdosis_reference_staging.commercial_product_enrichment` y `commercial_label_regimens`.

**Selección:** 8 fichas `index_only`, excluyendo 16 fichas en trabajo de lotes 33–48 y 662 fichas asignadas a Grok en la hoja de Drive. Orden por `commercial_products_intake.id` tras excluir las 16 fichas; desplazamiento de 662 para no invadir el lote de Grok. La distribución por lotes no equivale a validación clínica.

**Resultado de escritura y lectura posterior:** 8 enriquecimientos actualizados, 16 pautas registradas. 5 productos `conflict`, 3 `manufacturer_checked`. Todos con `medical_review_state=needs_review`; pautas `pending_clinical_review` o `conflict_needs_resolution`. No se modificaron tablas clínicas, no se habilitó cálculo ni prescripción automática.

## 1. BOLFO SHAMPOO — Elanco (1 pauta)
- **Fórmula:** propoxur 0.10% (1 g/L), shampoo; caninos y felinos.
- **Presentación:** PLM menciona 350 mL, no corroborada en PDF oficial 08/2022.
- **Pauta:** cantidad suficiente para espuma abundante, enjuague, repetición y segundo contacto durante algunos minutos; vía tópica, sin dosis proporcional al peso ni frecuencia fija. PLM precisa 3–5 min.
- **Seguridad:** fabricante desaconseja uso en menores de 1 mes, lesiones cutáneas, ciertas afecciones respiratorias/cardiovasculares y obstrucciones; prohibido en animales para consumo humano. No hay retiro numérico.
- **Alerta:** referencia de registro oficial RSCO-PEC-INAC-0186-306-340-0.10 frente a RACO-INAC-186-15-0615-039 en PLM; fuente oficial de 2022.
- **Fuente:** https://assets.elanco.com/8e0bf1c2-1ae4-001f-9257-f2be3c683fb1/e1f3a891-19c4-4087-a04f-7a2be6839ab9/FT_Bolfo%20Shampoo_MX_8-2022.pdf ; https://www.diccionarioveterinarioplm.com/bolfo_shampoo-45-15079-147-338-2

## 2. BRONQUIVET NF — Riverfarma (4 pautas)
- **Fórmula:** por 100 mL, guayacol 10 g + carbocisteína 20 g + piroxicam 2 g; inyectable, frasco 50 mL, registro Q-0524-057.
- **Pautas IM cada 24 h por 5 días:** bovinos/equinos 1 mL/66 kg; ovinos/caprinos 0.5 mL/33 kg; porcinos 1 mL/20 kg; caninos/felinos 0.12 mL/8 kg. Todas proporcionales por peso, no dosis fijas por animal.
- **Retiros:** carne 4 días, leche 96 h; no usar en equinos de consumo humano. Conservar 15–30 °C.
- **Alerta:** el índice inicial solo incluía guayacol y piroxicam; la ficha del fabricante añade carbocisteína.
- **Fuente:** https://www.riverfarma.com.mx/content/uploads/downloads/Bronquivet-NF.pdf

## 3. ERICLOR AVÍCOLA — Parfarm (3 pautas)
- **Fórmula por gramo:** sulfacloropiridazina sódica 300 mg, trimetoprim 150 mg, doxiciclina hiclato 100 mg, diclofenaco 5 mg. Polvo para solución oral; aves productoras, reproductoras, progenitoras y de engorda. Registro Q-0021-050.
- **Pautas comerciales:** preventiva 1 g/L de agua, preventiva 500 g/ton de alimento, curativa 2 g/L de agua. Estas son concentraciones en vehículo, **no mg/kg de peso vivo**. Duración no especificada.
- **Presentación:** tarro 100 g o caja de 50 sobres de 10 g. **Retiros fabricante:** carne 7 días antes del sacrificio; huevos 6 días desde última administración.
- **Alerta grave:** distribuidor publica 1000 g/ton, carne 30 días y huevos 24 h; discrepancia frente al fabricante (500 g/ton, 7 días y 6 días). No normalizar ni extrapolar.
- **Fuentes:** https://www.parfarm.com/productos/ericlor-av%C3%ADcola ; https://alamazonas.com.mx/products/ericlor-avicola

## 4. SCABISIN CALM — Chinoin (1 pauta)
- **Ingredientes:** pramoxina clorhidrato, extracto de avena, avena coloidal, alantoína; shampoo para caninos/felinos, 350 mL.
- **Pauta:** aplicar al pelo húmedo hasta espumar, esperar unos minutos, enjuagar; repetir cada 2–3 semanas a criterio MVZ; vía tópica.
- **Alerta de formulación:** PLM muestra un renglón combinado con «1 g/100 mL», que no permite asignar con seguridad el número a un ingrediente concreto sin marbete; web oficial no cuantifica. No registrar concentración numérica como confirmada. Registro Q-0895-123 solo según PLM. La web Chinoin muestra copyright 2017; PLM advierte posible desactualización.
- **Fuente:** https://www.chinoinveterinaria.com/sitio/scabisin_calm.html ; https://www.diccionarioveterinarioplm.com/scabisin_calm-76-16142-147-13-2

## 5. EMULMAX -C N5 — Sanfer (2 pautas)
- **Formulación:** vacuna inactivada Newcastle cepa rP05 (Genotipo V), emulsión en aceite mineral; frasco 500 mL/2500 dosis; registro B-10575-060.
- **Pautas:** aves de 1 día, 0.2 mL/ave SC en tercio medio posterior del cuello; aves de 8 días o más, 0.3–0.4 mL/ave SC. Son **dosis fijas por ave y umbrales de edad**, no mg/kg.
- **Condiciones:** refrigerar 2–8 °C, no congelar, agitar y atemperar antes de aplicación. Retiro no declarado, no equivale a cero.
- **Alerta:** la equivalencia 500 mL/2500 dosis solo aplica al volumen 0.2 mL; no extrapolar el rendimiento del frasco a 0.3–0.4 mL. No confundir con otras vacunas Emulmax.
- **Fuente:** https://admin.sanfersaludanimal.com/images/fichas/1596604937Emulmax-C%20N5%20.pdf

## 6. EPIC SHAMPOO — Halvet (1 pauta)
- **Formulación elegida:** EPIC SHAMPOO **líquido** con ceramidas 0.05% y excipientes; frasco 200 mL, vía cutánea. Especie no textual en extracto revisado, no inferir automáticamente.
- **Pauta:** aplicar cantidad suficiente sobre pelo húmedo, masajear, dejar 3–5 min y enjuagar. Sin dosis en mL ni intervalo fijo.
- **Alerta:** Halvet también comercializa EPIC SHAMPOO **crema** 0.2%, envase 60 g. PLM mezcla en narrativa referencias a crema dentro de ficha de líquido. No fusionar fórmulas. Retiro no declarado.
- **Fuente:** https://www.halvet.com/catalogo/wp-content/uploads/2024/04/TC-001-GP-2024-DESCARGA.pdf ; https://www.diccionarioveterinarioplm.com/epic_shampoo-76-15427-137-119-2

## 7. CLINDAMICINA CHEMINOVA — Cheminova (3 pautas)
- **Fórmula:** fosfato de clindamicina 12 g/100 mL, equivalente a clindamicina base 10 g/100 mL (100 mg/mL base). Inyectable; PLM indica frasco 100 mL, vías IM, SC e infusión IV. Registro Q-7048-054.
- **Pautas proporcionales:** bovinos de carne y porcinos 10 mL/100 kg cada 12–24 h; caninos y felinos 0.5–1 mL/10 kg cada 12–24 h por 4–7 días; toxoplasmosis 2.5 mL/10 kg cada 12 h.
- **Alertas:** fabricante menciona duración para toxoplasmosis de 2 semanas en encabezado y 2–4 semanas en tabla. Vía y presentación documentadas por PLM, no verificadas directamente en web fabricante consultada.
- **Seguridad/retiro:** no usar en equinos, cobayos, conejos, hámsteres; carne 4 días tras última dosis, contraindicado en bovinos productores de leche destinada al consumo humano.
- **Fuentes:** https://cheminovavet.com.mx/product/clindamicina-cheminova/ ; https://www.diccionarioveterinarioplm.com/clindamicina_cheminova-76-1545-10-12-2

## 8. TEAR FUNCTION CHEMINOVA — Cheminova (1 pauta)
- **Fórmula:** ciclosporina A 10 mg/mL (1%), solución oftálmica; frasco gotero 10 mL según PLM, registro Q-7048-084.
- **Pauta:** una gota por ojo cada 12 h, puede requerir mantenimiento prolongado bajo criterio MVZ; aplicación oftálmica, dosis fija por ojo, no por peso.
- **Seguridad:** evitar contacto cutáneo, suspender ante hipersensibilidad; PLM condiciona uso felino a criterio/responsabilidad MVZ. Retiro no declarado.
- **Alerta:** la expresión «saco subconjuntival» de la ficha no debe interpretarse como indicación de inyección; confirmar redacción anatómica con marbete.
- **Fuentes:** https://cheminovavet.com.mx/product/tear-function-cheminova/ ; https://www.diccionarioveterinarioplm.com/tear_function_cheminova-76-16427-117-12-2

## Control de calidad y pendientes
- **Pautas totales:** 16 (1 + 4 + 3 + 1 + 2 + 1 + 3 + 1). Las unidades no comparables (g/L, g/ton, mL/kg, mL/ave, gotas/ojo, baños) no se convierten a una dosis clínica universal.
- **Alertas:** 5 productos con conflicto documental; las advertencias adicionales de los otros 3 se conservan sin forzar estado `conflict`.
- **Base de datos al finalizar:** 1315 `index_only`; 33 `manufacturer_checked`; 23 `plm_detail_checked`; 13 `conflict` (total 1384).
- **Estado:** fuentes comerciales/documentales, no validación terapéutica MVZ. No se habilitó ninguna función automática. Los datos ausentes permanecen ausentes, nunca se interpretan como 0.
