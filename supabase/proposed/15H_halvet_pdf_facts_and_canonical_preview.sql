-- Private PDF facts and non-destructive preview: never erase PLM sources.
begin;
alter table vetdosis_reference_staging.manufacturer_pdf_product_index
 add column if not exists document_facts jsonb not null default '{}'::jsonb;
alter table vetdosis_reference_staging.manufacturer_pdf_product_index
 add column if not exists document_facts_page integer;
create or replace view vetdosis_reference_staging.commercial_catalog_review_preview
with (security_invoker=true) as
select c.product_url as catalog_record_key,
 c.product_name as display_name,
 c.manufacturer_raw as manufacturer,
 c.dosage_form as dosage_form,
 'PLM_index'::text as canonical_source,
 case when exists (
  select 1 from vetdosis_reference_staging.manufacturer_pdf_product_index p
  where p.candidate_plm_product_url=c.product_url
 ) then 'PLM_with_manufacturer_pdf_candidate'::text else 'PLM_only'::text end as review_status
from vetdosis_reference_staging.commercial_products_intake c
union all
select 'pdf:'||p.source_sha256||'#'||p.source_item_number as catalog_record_key,
 p.product_name_in_pdf as display_name,
 'HALVET'::text as manufacturer,
 coalesce(p.document_facts->>'dosage_form','Pendiente de verificar') as dosage_form,
 'manufacturer_pdf'::text as canonical_source,
 'PDF_only_candidate_unverified'::text as review_status
from vetdosis_reference_staging.manufacturer_pdf_product_index p
where p.reconciliation_status='pdf_only_candidate';
revoke all on vetdosis_reference_staging.commercial_catalog_review_preview from public,anon,authenticated;
commit;