-- VetDosis: intake RAW nonclinical of bibliographic spreadsheets, after reviewed 15A.
-- ADDITIVE ONLY. No client grants. This is NOT a clinically approved catalogue.
begin;

create table if not exists vetdosis_reference_staging.raw_intake_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references vetdosis_reference_staging.import_batches(id) on delete restrict,
  row_key text not null check (length(btrim(row_key)) between 1 and 240),
  source_filename text not null,
  source_sheet text not null,
  source_row integer not null check (source_row >= 2),
  source_title text,
  original_payload jsonb not null check (jsonb_typeof(original_payload)='object'),
  row_sha256 text not null check (row_sha256 ~ '^[a-f0-9]{64}$'),
  review_state text not null default 'pending' check (review_state in ('pending','conflict','rejected')),
  ingestion_note text not null default 'Imported verbatim; not clinically validated',
  recorded_at timestamptz not null default now(),
  constraint reference_raw_batch_row_unique unique (batch_id,row_key)
);

create index if not exists reference_raw_intake_state_idx
  on vetdosis_reference_staging.raw_intake_rows (review_state,batch_id);
alter table vetdosis_reference_staging.raw_intake_rows enable row level security;
revoke all on vetdosis_reference_staging.raw_intake_rows from public,anon,authenticated;
alter default privileges in schema vetdosis_reference_staging revoke all on tables from public;
commit;
