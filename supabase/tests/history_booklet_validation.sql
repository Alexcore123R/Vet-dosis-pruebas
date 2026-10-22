-- Isolated synthetic schema for the NEW trigger; never run against Supabase.
create schema private;
create role anon;
create role authenticated;
create table public.vet_patient_events(kind text, payload jsonb);
\ir ../adaptations/patient_history_booklet_v1.sql
begin;
-- Legacy rows remain readable and are not relabelled.
insert into public.vet_patient_events values ('preventive','{"product":"Synthetic"}');
insert into public.vet_patient_events values ('preventive',
 '{"preventive_version":1,"origin":"owner_report","date_precision":"unknown","product":"No especificado","coverage":"Synthetic","informant":"Synthetic","date_description":"","performer":"","evidence_reference":"","next_date_by":""}');
do $$
declare base jsonb := '{"preventive_version":1,"origin":"owner_report","date_precision":"unknown","product":"No especificado","coverage":"Synthetic","informant":"Synthetic","date_description":"","performer":"","evidence_reference":"","next_date_by":""}';
        bad jsonb;
begin
  for bad in select value from jsonb_array_elements('[
    {"origin":"invalid"}, {"origin":"clinic","performer":"Synthetic"},
    {"origin":"external_document"}, {"informant":""},
    {"date_precision":"approximate"}, {"next_date":"2026-11-01"},
    {"preventive_version":2}, {"coverage":42}
  ]') loop
    begin
      insert into public.vet_patient_events values ('preventive',base||bad);
      raise exception 'test_expected_rejection';
    exception when raise_exception then
      if sqlerrm='test_expected_rejection' then raise; end if;
    end;
  end loop;
end $$;
do $$ begin
  if exists(select 1 from public.vet_patient_events
    where not(payload ? 'preventive_version') and payload ? 'origin') then
    raise exception 'legacy_origin_was_invented';
  end if;
end $$;
rollback;
