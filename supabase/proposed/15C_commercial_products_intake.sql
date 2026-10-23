-- ADDITIVE: PLM/PEV commercial product index supplied by the VetDosis owner.
-- Private archival/review snapshot. Not a licensed public API, clinical label,
-- approved dosage catalog, or permission to distribute any third-party content.
begin;

create table if not exists vetdosis_reference_staging.commercial_products_intake (
  id uuid primary key default gen_random_uuid(),
  source_catalog text not null default 'PLM PEV Mexico',
  product_url text not null unique check (length(btrim(product_url)) > 12),
  product_name text not null check (length(btrim(product_name)) > 0),
  dosage_form text,
  substances_raw text,
  manufacturer_raw text,
  description_raw text,
  source_page text,
  source_file text,
  initial_letter text,
  observed_in_files jsonb not null default '[]'::jsonb check (jsonb_typeof(observed_in_files) = 'array'),
  original_payload jsonb not null check (jsonb_typeof(original_payload) = 'object'),
  review_state text not null default 'pending_source_review' check (
    review_state in ('pending_source_review','conflict','rejected')
  ),
  created_at timestamptz not null default now()
);
create index if not exists commercial_products_review_idx
  on vetdosis_reference_staging.commercial_products_intake(review_state,initial_letter);
alter table vetdosis_reference_staging.commercial_products_intake enable row level security;
revoke all on vetdosis_reference_staging.commercial_products_intake from public,anon,authenticated;
revoke all on schema vetdosis_reference_staging from public,anon,authenticated;

commit;
