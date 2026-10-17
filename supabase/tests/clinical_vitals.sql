-- Synthetic structured vital snapshot. No clinical ranges or recommendations are inferred.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic clinical permission A' \gset
select id as case_id from public.clinical_cases where clinic_id=:'clinic' and title='Synthetic case' \gset

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select set_config(
 'test.vitals',
 jsonb_build_object(
  'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'performed_by',auth.uid(),
  'fc','85','fr','22','temperature','38.5','tllc','1.5',
  'bp_systolic','125','bp_diastolic','75',
  'mucosa_color','rosadas','mucosa_humidity','humedas',
  'notes','Synthetic physical examination'
 )::text,
 false
);
select public.clinical_vitals_add(:'case_id',current_setting('test.vitals')::jsonb,repeat('7',48)) as vital \gset
select public.clinical_vitals_add(:'case_id',current_setting('test.vitals')::jsonb,repeat('7',48)) as retry \gset
select pg_temp.assert_true(:'vital'::jsonb->>'id'=:'retry'::jsonb->>'id','retry duplicated vital snapshot');
select pg_temp.assert_true(abs((:'vital'::jsonb->>'pam')::numeric-91.6666666666666667)<0.000001,'PAM calculation mismatch');
select pg_temp.assert_true(:'vital'::jsonb->>'mucosa_color'='rosadas','mucosa color missing');
select pg_temp.assert_true(not(:'vital'::jsonb ? 'triage_status'),'server invented a diagnostic triage status');
select pg_temp.assert_true(
 exists(
  select 1 from jsonb_array_elements(public.clinical_case_snapshot(:'case_id')->'vitals') v
  where v->>'id'=:'vital'::jsonb->>'id' and v->>'bp_systolic'='125.000000000'
 ),
 'snapshot does not expose structured vitals'
);
select pg_temp.assert_true(
 (public.clinical_case_snapshot(:'case_id')->'case'->>'patient_species')='synthetic',
 'case snapshot missing patient species'
);

select pg_temp.expect_error(
 format(
  $q$select public.clinical_vitals_add(%L::uuid,%L::jsonb,%L)$q$,
  :'case_id',
  (current_setting('test.vitals')::jsonb-'bp_diastolic')::text,
  repeat('8',48)
 ),
 'paired_blood_pressure_required'
);
select pg_temp.expect_error(
 format(
  $q$select public.clinical_vitals_add(%L::uuid,%L::jsonb,%L)$q$,
  :'case_id',
  (current_setting('test.vitals')::jsonb||'{"mucosa_color":"verde"}'::jsonb)::text,
  repeat('9',48)
 ),
 'invalid_vital_set'
);
select pg_temp.expect_error(
 format(
  $q$select public.clinical_vitals_add(%L::uuid,%L::jsonb,%L)$q$,
  :'case_id',
  '{"observed_at":"2026-10-17T00:00:00Z","performed_by":"00000000-0000-0000-0000-000000000111"}',
  repeat('a',48)
 ),
 'empty_vital_set'
);
reset role;

-- A member without case observation authority cannot write a snapshot.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000113',false);
set role authenticated;
select pg_temp.expect_error(
 format(
  $q$select public.clinical_vitals_add(%L::uuid,%L::jsonb,%L)$q$,
  :'case_id',
  current_setting('test.vitals'),
  repeat('b',48)
 ),
 'procedure_authorization_required'
);
reset role;

-- Structured facts are append-only even to a database owner.
select pg_temp.expect_error(
 format(
  $q$update public.clinical_vital_sets set notes='changed' where id=%L::uuid$q$,
  :'vital'::jsonb->>'id'
 ),
 'clinical_record_is_immutable_append_correction'
);
