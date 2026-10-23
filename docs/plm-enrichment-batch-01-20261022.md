# VetDosis — búsqueda web de fichas comerciales, lote 01
Fecha de revisión documental: **22 de octubre de 2026**. Entorno: Supabase Pruebas (`wtrelwtztkddfktrfdpb`). Investigación documental, **NO validación clínica**.

## Resultado de esta tanda
- **14** enlaces de producto distintos cotejados individualmente (en varias formulaciones): 3 ACTUOL, ADEFORT, ADENOVAC, ADRECAINE, ADVANTAGE, ADVANTAGE MULTI perros, ADVANTE MULTI gatos/hurones, ADVANTIX, ALIN, ALIN DEPOT, ALBEN MAX PUPPY, ALBAN 10 %.
- **25** pautas resumidas y rastreables registradas en la tabla privada `vetdosis_reference_staging.commercial_label_regimens` (migración aditiva 15E).
- **3** pautas con conflicto documental explícito; **3** tienen etiqueta pendiente de actualización (códigos `needs_current_label`), **19** pendientes de revisión clínica ordinaria.
- Balance conjunto: 1,384 productos comerciales, **24** con consulta individual de ficha técnica, **1,360** en índice sin consulta individual. Del total 4 contrastados con fabricante (incluido ORALVITPAN de lote previo) y 20 con ficha PLM. Ninguno aprobado para automatizar dosis en la app.
- Cada pauta conserva: producto, formulación, especie, clase de regla, dosis resumida (si procede), frecuencia, vía, fuente y fecha, incidencias; no se publican páginas copiadas.

## Qué tipos de reglas encontramos
| Tipo | Casos de esta tanda | Consecuencia para UI |
| --- | --- | --- |
| Proporcional a kg | ACTUOL 10 % suspensión, ALBEN MAX PUPPY, ALBAN 10 % | Cantidad por peso, únicamente al haber dosis/presentación/indicación específicas revisadas |
| Fija por animal | ADENOVAC, ALIN tabletas, hurones ADVANTAGE MULTI, ALIN DEPOT (algunas especies) | El peso no cambia el resultado de la indicación, pero no sustituye prescripción |
| Bandas de peso | ADVANTAGE, ADVANTAGE MULTI perros, ADVANTIX | Selector de pipeta por intervalo; no hacer regla lineal |
| Rangos o condiciones especiales | ADRECAINE, ADEFORT, ACTUOL granulado | Consulta de etiqueta; no un resultado automático aislado |
| Revisión obligatoria por conflicto | ACTUOL 4 % polvo; ADVANTAGE; ADVANTAGE MULTI perros | Bloquear uso automático hasta contrastar con envase / laboratorio |

## ALERTAS documentales

1. **ACTUOL polvo 4 %, Senosiain**: [documento de fabricante, pág. 1](https://senosiain.mx/wp-content/uploads/2021/06/actuol-IPP.pdf): en prosa imprime **12.5 g/kg** en porcinos, pero inmediatamente debajo su tabla expresa **12.5 g para 100 kg**. Discrepancia de cien veces. Ninguna de las dos lecturas puede publicarse como dosis automática hasta obtener rectificación técnica. El PDF también incluye las tres presentaciones ACTUOL; no asignar referencias de suspensión a polvo o granulado por compartir marca.
2. **ADVANTAGE**: [ficha PLM](https://www.diccionarioveterinarioplm.com/advantage-146-15054-153-338-2) muestra signos de bandas de peso que no parecen coherentes para gato/perro; verificar frente a envase actual de Elanco.
3. **ADVANTAGE MULTI perros**: [ficha PLM](https://www.diccionarioveterinarioplm.com/advantage_multi_perros-146-15676-153-338-2) enumera solamente imidacloprid en encabezado, pero describe moxidectina en el cuerpo, y los extremos de peso de pipetas requieren verificación. No usar el índice como composición completa.
4. **ADENOVAC**: [ficha PLM](https://www.diccionarioveterinarioplm.com/adenovac-76-15435-243-13-2) informa dosis por animal y advertencia editorial de posible desactualización, por tanto requiere confirmar esquema vigente.
5. **ADVANTIX**: [ficha PLM](https://www.diccionarioveterinarioplm.com/advantix-45-15056-153-338-2) restringe el uso a perros y advierte no utilizar en gatos ni cachorros menores de 2 meses.
6. **ALIN tabletas**: [ficha PLM](https://www.diccionarioveterinarioplm.com/alin-76-391-14-13-2) contiene múltiples indicaciones que no deben fusionarse en un único algoritmo. La dosificación transcrita en staging para perros/gatos **no supone aprobación clínica**.
7. **ADEFORT**: [ficha PLM](https://www.diccionarioveterinarioplm.com/ADEFORT-76-3224-10-9-2) incluye perros y gatos en especies, pero la tabla transcrita del pasaje accesible no aporta cantidades para ellos. Marcar dosis faltante.

## Fuentes del lote
- Fabricante: [ACTUOL — Laboratorios Senosiain](https://senosiain.mx/708-2/); [IPP PDF oficial (3 págs.)](https://senosiain.mx/wp-content/uploads/2021/06/actuol-IPP.pdf).
- [ADEFORT](https://www.diccionarioveterinarioplm.com/ADEFORT-76-3224-10-9-2)
- [ADENOVAC](https://www.diccionarioveterinarioplm.com/adenovac-76-15435-243-13-2)
- [ADRECAINE](https://www.diccionarioveterinarioplm.com/adrecaine-76-5354-10-174-2)
- [ADVANTAGE](https://www.diccionarioveterinarioplm.com/advantage-146-15054-153-338-2)
- [ADVANTAGE MULTI perros](https://www.diccionarioveterinarioplm.com/advantage_multi_perros-146-15676-153-338-2)
- [ADVANTE MULTI gatos y hurones](https://www.diccionarioveterinarioplm.com/advante_multi_gatos_y_hurones-146-15678-153-338-2)
- [ADVANTIX](https://www.diccionarioveterinarioplm.com/advantix-45-15056-153-338-2)
- [ALIN tabletas](https://www.diccionarioveterinarioplm.com/alin-76-391-14-13-2)
- [ALIN DEPOT](https://www.diccionarioveterinarioplm.com/alin_depot-76-392-108-13-2)
- [ALBEN MAX PUPPY](https://www.diccionarioveterinarioplm.com/alben_max_puppy-76-13319-156-241-2)
- [ALBAN 10 %](https://www.diccionarioveterinarioplm.com/alban_10-76-2125-21-31-2)

## Consultas de control
```sql
select count(*) as total_products
from vetdosis_reference_staging.commercial_products_intake;

select review_state,count(*) as products
from vetdosis_reference_staging.commercial_product_enrichment
group by 1 order by 1;

select label_dosing_type,review_state,count(*) as rules
from vetdosis_reference_staging.commercial_label_regimens
group by 1,2 order by 1,2;
```

## Pendiente / prohibiciones
- No activar en DoseScreen ninguna pauta todavía: falta revisión MVZ y etiqueta vigente, más motores de `fixed_per_animal`, `weight_band`, `weight_threshold`, `fixed_range`, `label_complex`.
- Los productos comerciales de nombre repetido que apunten a variantes diferentes deben mapearse por presentación; otras dos URLs ACTUOL no accesibles siguen pendientes.
- Datos comerciales, farmacología por principio activo y valores de referencia hematológica/constantes permanecen en catálogos separados.
- No reproducir textos completos, fotografías ni tablas editoriales en publicación; conservar hechos extraídos con atribución.
