# VetDosis — completar fichas individuales PLM / laboratorio

**Corte:** 22 de octubre de 2026. **Entorno remoto:** Supabase Pruebas, proyecto `wtrelwtztkddfktrfdpb`.

## Estado comprobado

- `vetdosis_reference_staging.commercial_products_intake`: 1,384 productos comerciales recibidos de 27 archivos HTML, 1,384 enlaces únicos. La importación previa se conserva intacta.
- Migración de preparación `15D_commercial_product_enrichment.sql` ejecutada y versionada en esta rama.
- `vetdosis_reference_staging.commercial_product_enrichment`: 1,384 filas privadas ligadas por URL a su ficha de catálogo.
- Al iniciar esta fase, 9 productos verificados contra su ficha técnica individual PLM: ABADOL, ABSORVET, ACATAN CE, ACTINOBACT-P, ACUAPEN, ADEBON-9 (una formulación), CARPROBAY 20 mg, ONSIOR e IMIDOZOL.
- 1 producto cotejado directamente con el fabricante PANAVET: ORALVITPAN, cuya descripción estaba vacía en la página alfabética. La página individual de PLM no resultó accesible, por lo que se utilizó la fuente primaria.
- **Balance:** 10 revisados (9 PLM + 1 fabricante), 1,374 en `index_only` aún sin comprobación individual. Ninguna ficha tiene `medical_review_state=verified_by_vet`.
- PLM presenta tanto fichas marcadas actualizadas como fichas con advertencia de posible desactualización; esa distinción se preserva en `source_claim_status`.

## Campos a completar en cada ficha

`target_species`, `administration_route`, `concentration_fact`, `presentation_fact`, `registration_reference`, `withdrawal_fact`, `safety_fact`, `source_url`, `checked_on`, `source_claim_status`. Especies y tiempos de retiro no aplican a todo tipo de producto: jamás forzarlos ni confundir NO CONSTA con NO APLICA.

Mantener separados medicamentos, biológicos, nutricionales, plaguicidas, productos para instalaciones y cosméticos. El index tiene nombres, formas, sustancias y fabricantes; eso no implica que una ficha individual esté validada.

## Flujo para los 1,374 restantes

1. Obtener lista pendiente mediante consulta de solo lectura desde la base de pruebas (abajo).
2. Acceder a la ficha técnica individual, respetando las condiciones de uso y `robots.txt` del proveedor. Priorizar fuentes propias de cada fabricante cuando existan; no extraer ni republicar textos, fotografías o tablas completos.
3. Anotar solamente hechos verificables, con URL y fecha. Guardar distinción entre etiquetas publicadas, publicidad y validación documental independiente; señalar contradicciones de especie, fórmula, concentración, presentación o registro.
4. Generar candidatos en lotes pequeños y revisar manualmente antes de hacer UPDATE a staging. No promover datos a `public."Fármacos"`, medicación clínica, recetas ni motor de dosis.
5. Revisar alertas con MVZ antes de habilitar información clínica en UI, y verificar cualquier producto frente a regulación mexicana actual.

```sql
select c.product_name,c.product_url
from vetdosis_reference_staging.commercial_products_intake c
join vetdosis_reference_staging.commercial_product_enrichment e using(product_url)
where e.review_state='index_only'
order by c.product_name,c.product_url
limit 25;
```

## Hallazgos que requieren atención

- **CARPROBAY 20 mg:** ficha PLM indica contraindicación en gatos y avisa que podría no estar actualizada.
- **ADEBON-9:** la formulación consultada no garantiza estar actualizada; hay al menos otra URL/variante del mismo nombre.
- **ACATAN CE:** clasificar como plaguicida / ectoparasiticida; ficha incluye toxicidad ambiental y tiempos de retiro, no debe tratarse como una presentación oral/injectable común.
- **ACTINOBACT-P:** bacterina, no antibiótico. Requiere control como biológico.
- **ORALVITPAN:** fabricante PANAVET describe el producto como suplemento vitamínico oral; no inventar registro sanitario.
- **ONSIOR:** ficha especifica tabletas 10/20/40 mg; la presentación comercial por caja no estaba especificada en el pasaje revisado.

## Seguridad

Esquema `vetdosis_reference_staging` privado; las tablas de ingreso no otorgan `SELECT` a `anon` ni `authenticated` y cuentan con RLS. La tabla `commercial_product_enrichment` tampoco tiene acceso para cliente; sus datos no se consumen en tiempo real en VetDosis.

No existe una automatización ejecutándose en segundo plano. Como ayuda para iniciar lotes desde un entorno con acceso web, se generó el paquete local `VetDosis_PLMCatalogo_herramienta_revision_20261022.zip` con índice y script conservador (máximo 25 URL por ejecución, revisa robots y no importa datos); sus resultados son **candidatos** y requieren cotejo humano.

**Fuentes de la primera tanda:** enlaces individuales conservados en `source_url` y página del fabricante `https://www.panavet.com.mx/catalog/panavet-oralvitpan.html`.
