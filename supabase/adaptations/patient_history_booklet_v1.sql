-- NEW additive validation only. Never rerun historical deployment scripts 01-08.
-- Review against the actual remote schema before applying. Does not grant clinical
-- authority, reopen add_vet_patient_event, alter RLS or activate admissions.
begin;
create function private.validate_patient_history_booklet_v1()
returns trigger language plpgsql set search_path = '' as $$
declare d jsonb := new.payload; k text; origin text; precision text;
begin
  if new.kind = 'soap' and d->>'record_type' = 'clinical_history' then
    foreach k in array array['medical_history','surgical_history','current_treatments',
      'family_history','feeding','environment','reproductive_history','anamnesis',
      'physical_exam','vital_signs','problem_list','diagnostic_studies','follow_up'] loop
      if jsonb_typeof(d->k) is distinct from 'string' or length(d->>k)>4000 then
        raise exception 'invalid_history_section';
      end if;
    end loop;
  end if;
  if new.kind = 'preventive' and d ? 'preventive_version' then
    if d->'preventive_version' is distinct from '1'::jsonb then
      raise exception 'unsupported_preventive_version';
    end if;
    origin := d->>'origin'; precision := d->>'date_precision';
    if origin is null or origin not in ('clinic','external_document','owner_report')
      or precision is null or precision not in ('exact','approximate','unknown')
      or (origin='clinic' and precision<>'exact') then
      raise exception 'invalid_preventive_origin_or_date';
    end if;
    foreach k in array array['coverage','date_description','performer','informant',
      'evidence_reference','next_date_by'] loop
      if jsonb_typeof(d->k) is distinct from 'string' or length(d->>k)>1000 then
        raise exception 'invalid_preventive_metadata';
      end if;
    end loop;
    if (origin='clinic' and btrim(d->>'performer')='')
      or (origin='external_document' and btrim(d->>'evidence_reference')='')
      or (origin='owner_report' and btrim(d->>'informant')='')
      or (precision='approximate' and btrim(d->>'date_description')='')
      or (d->>'next_date' is not null and btrim(d->>'next_date_by')='')
      or (btrim(coalesce(d->>'product',''))='' and btrim(d->>'coverage')='') then
      raise exception 'incomplete_preventive_metadata';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.validate_patient_history_booklet_v1() from public, anon, authenticated;
create trigger validate_patient_history_booklet_v1 before insert on public.vet_patient_events
for each row execute function private.validate_patient_history_booklet_v1();
commit;
