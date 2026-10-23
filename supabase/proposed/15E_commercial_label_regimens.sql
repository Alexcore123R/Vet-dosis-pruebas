-- VetDosis label-only staging; typed dosing patterns; never promoted to prescribing/dose engine.
begin;
create table if not exists vetdosis_reference_staging.commercial_label_regimens (
 id uuid primary key default gen_random_uuid(),
 product_url text not null references vetdosis_reference_staging.commercial_products_intake(product_url) on delete restrict,
 regimen_key text not null,
 formulation_label text not null,
 species_label text not null,
 indication_label text,
 label_dosing_type text not null check (label_dosing_type in (
  'proportional_weight','fixed_per_animal','weight_band','weight_threshold',
  'fixed_range','feed_concentration','label_complex','label_unresolved')),
 label_instruction_summary text not null,
 amount numeric(24,9),
 amount_unit text,
 per_weight_kg numeric(24,9),
 frequency_text text,
 administration_route text,
 source_url text not null,
 source_type text not null check (source_type in ('manufacturer_page','plm_technical_page')),
 source_checked_on date not null,
 review_state text not null default 'pending_clinical_review'
  check (review_state in ('pending_clinical_review','conflict_needs_resolution','needs_current_label','rejected')),
 cautions jsonb not null default '[]'::jsonb check (jsonb_typeof(cautions)='array'),
 created_at timestamptz not null default now(),
 unique(product_url,regimen_key),
 check(amount is null or amount>0),
 check(per_weight_kg is null or per_weight_kg>0),
 check(label_dosing_type <> 'proportional_weight' or
   (amount is not null and amount_unit is not null and per_weight_kg is not null)),
 check(label_dosing_type <> 'fixed_per_animal' or
   (amount is not null and amount_unit is not null))
);
create index if not exists commercial_label_regimens_product_idx on vetdosis_reference_staging.commercial_label_regimens(product_url);
create index if not exists commercial_label_regimens_review_idx on vetdosis_reference_staging.commercial_label_regimens(review_state,label_dosing_type);
alter table vetdosis_reference_staging.commercial_label_regimens enable row level security;
revoke all on vetdosis_reference_staging.commercial_label_regimens from public,anon,authenticated;
commit;