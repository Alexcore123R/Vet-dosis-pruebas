-- VetDosis: zona de ingreso de referencias bibliográficas, SIN publicación clínica.
-- Propuesta únicamente: no ejecutar en Supabase remoto hasta aprobarla.
-- Separa el material extraído de los valores clínicos que algún día sean aprobados.
begin;

create schema if not exists vetdosis_reference_staging;
revoke all on schema vetdosis_reference_staging from public;

create table if not exists vetdosis_reference_staging.sources (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique check (length(btrim(source_key)) between 1 and 160),
  title text not null check (length(btrim(title)) between 1 and 600),
  source_type text not null check (
    source_type in ('book','article','official_label','laboratory','teaching_material','other')
  ),
  author_editor text,
  edition text,
  publication_year integer check (publication_year between 1800 and 2100),
  publication_details text,
  source_url text,
  provenance_notes text,
  recorded_at timestamptz not null default now()
);

create table if not exists vetdosis_reference_staging.import_batches (
  id uuid primary key default gen_random_uuid(),
  batch_key text not null unique check (length(btrim(batch_key)) between 1 and 160),
  label text not null check (length(btrim(label)) between 1 and 300),
  origin_filename text,
  original_sha256 text check (original_sha256 is null or original_sha256 ~ '^[a-f0-9]{64}$'),
  ingestion_notes text,
  created_at timestamptz not null default now()
);

create table if not exists vetdosis_reference_staging.candidates (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references vetdosis_reference_staging.import_batches(id) on delete restrict,
  source_id uuid not null references vetdosis_reference_staging.sources(id) on delete restrict,
  row_key text not null check (length(btrim(row_key)) between 1 and 240),
  category text not null check (category in (
    'physiology','laboratory','reproduction','incubation',
    'pharmacology','safety','equipment','other'
  )),
  species_label text not null check (length(btrim(species_label)) between 1 and 240),
  scientific_name text,
  parameter_label text not null check (length(btrim(parameter_label)) between 1 and 240),
  source_locator text not null check (length(btrim(source_locator)) between 1 and 240),
  raw_value text not null check (length(btrim(raw_value)) between 1 and 2000),
  value_kind text not null check (value_kind in ('interval','point','upper_bound','lower_bound','unparsed')),
  value_min numeric(22,10),
  value_max numeric(22,10),
  unit_original text,
  unit_canonical text,
  context jsonb not null default '{}'::jsonb check (jsonb_typeof(context)='object'),
  original_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(original_payload)='object'),
  notes text,
  -- 'approved' intentionally does NOT exist here; promotion requires a separate reviewed catalogue.
  review_state text not null default 'pending' check (review_state in ('pending','conflict','rejected')),
  created_at timestamptz not null default now(),
  constraint reference_candidate_shape check (
    (value_kind='interval' and value_min is not null and value_max is not null and value_min<=value_max)
    or (value_kind='point' and value_min is not null and value_max is null)
    or (value_kind='lower_bound' and value_min is not null and value_max is null)
    or (value_kind='upper_bound' and value_min is null and value_max is not null)
    or (value_kind='unparsed' and value_min is null and value_max is null)
  ),
  constraint reference_candidate_batch_row_unique unique (batch_id,row_key)
);
create index if not exists reference_candidates_source_idx on vetdosis_reference_staging.candidates(source_id);
create index if not exists reference_candidates_review_idx on vetdosis_reference_staging.candidates(review_state,category);

-- No client access, no grants to anon/authenticated, no exposed public views or RPCs.
-- Even an accidental direct table grant cannot bypass the absence of RLS policies.
alter table vetdosis_reference_staging.sources enable row level security;
alter table vetdosis_reference_staging.import_batches enable row level security;
alter table vetdosis_reference_staging.candidates enable row level security;
revoke all on all tables in schema vetdosis_reference_staging from public;
alter default privileges in schema vetdosis_reference_staging revoke all on tables from public;

commit;
