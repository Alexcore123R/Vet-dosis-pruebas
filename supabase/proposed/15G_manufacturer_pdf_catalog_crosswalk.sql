-- Vendor PDFs: canonical source index and conservative non-destructive crosswalk.
-- Keep ALL source records; exact names are linked as candidates only.
begin;
create table if not exists vetdosis_reference_staging.manufacturer_pdf_sources(
 sha256 text primary key check (sha256 ~ '^[a-f0-9]{64}$'),
 filename text not null,
 page_count integer not null check (page_count>0),
 original_location_note text not null default 'User supplied conversation PDF; retained by user',
 intake_on date not null,
 imported_at timestamptz not null default now()
);
create table if not exists vetdosis_reference_staging.manufacturer_pdf_product_index(
 source_sha256 text not null references vetdosis_reference_staging.manufacturer_pdf_sources(sha256),
 source_item_number integer not null check(source_item_number>0),
 product_name_in_pdf text not null check(length(btrim(product_name_in_pdf))>0),
 pdf_index_page integer not null,
 pdf_page_candidates integer[] not null default '{}'::integer[],
 reconciliation_status text not null check(reconciliation_status in ('exact_PLM','possible_alias','pdf_only_candidate','manual_review')),
 candidate_plm_product_url text references vetdosis_reference_staging.commercial_products_intake(product_url),
 candidate_alias_name text,
 verification_state text not null default 'index_only' check(verification_state in ('index_only','detail_checked','conflict','rejected')),
 imported_at timestamptz not null default now(),
 primary key(source_sha256,source_item_number),
 unique(source_sha256,product_name_in_pdf)
);
create index if not exists manufacturer_pdf_index_status on vetdosis_reference_staging.manufacturer_pdf_product_index(reconciliation_status);
alter table vetdosis_reference_staging.manufacturer_pdf_sources enable row level security;
alter table vetdosis_reference_staging.manufacturer_pdf_product_index enable row level security;
revoke all on vetdosis_reference_staging.manufacturer_pdf_sources from public,anon,authenticated;
revoke all on vetdosis_reference_staging.manufacturer_pdf_product_index from public,anon,authenticated;
commit;