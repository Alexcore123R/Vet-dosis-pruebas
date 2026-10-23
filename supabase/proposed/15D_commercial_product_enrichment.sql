-- VetDosis enrichment staging: private structured facts sourced to individual product detail.
-- Source verification is NOT clinical approval or an authorization to display third-party content.
-- Additive; does not alter the commercial catalog, clinical medication tables or dosage engine.
begin;
create table if not exists vetdosis_reference_staging.commercial_product_enrichment (
 product_url text primary key references vetdosis_reference_staging.commercial_products_intake(product_url) on delete restrict,
 review_state text not null default 'index_only' check (review_state in
   ('index_only','plm_detail_checked','manufacturer_checked','conflict','unavailable')),
 source_url text,
 source_type text not null default 'index_page' check (source_type in ('index_page','plm_technical_page','manufacturer_document')),
 source_claim_status text not null default 'unknown' check (source_claim_status in
   ('unknown','publisher_marks_current','publisher_warns_may_be_outdated')),
 checked_on date,
 target_species text[] not null default '{}'::text[],
 administration_route text,
 concentration_fact text,
 presentation_fact text,
 registration_reference text,
 withdrawal_fact text,
 safety_fact text,
 external_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(external_evidence) = 'object'),
 medical_review_state text not null default 'not_reviewed' check (medical_review_state in ('not_reviewed','needs_review','verified_by_vet','rejected')),
 updated_at timestamptz not null default now(),
 constraint detail_requires_source check (
  review_state='index_only' or (source_url is not null and checked_on is not null)
 )
);
alter table vetdosis_reference_staging.commercial_product_enrichment enable row level security;
revoke all on vetdosis_reference_staging.commercial_product_enrichment from public,anon,authenticated;
insert into vetdosis_reference_staging.commercial_product_enrichment(product_url,source_url)
select product_url, product_url from vetdosis_reference_staging.commercial_products_intake
on conflict(product_url) do nothing;
commit;
