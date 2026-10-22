-- Synthetic backup scopes only. No real clinical content.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset

-- Give the clinic export real synthetic v2 booklet rows to preserve.
insert into public.vet_owners(clinic_id,name,phone,created_by)
values(:'clinic','Synthetic booklet owner','5550101','00000000-0000-0000-0000-000000000150')
returning id as booklet_owner \gset
insert into public.vet_patients(clinic_id,name,species,sex,owner_id,created_by)
values(:'clinic','Synthetic booklet patient','canino','sin especificar',:'booklet_owner','00000000-0000-0000-0000-000000000150')
returning id as booklet_patient \gset
insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by)
values(:'clinic',:'booklet_patient','preventive','{"date":"2026-10-20","type":"vacuna","coverage":"Synthetic coverage"}','00000000-0000-0000-0000-000000000150')
returning id as booklet_event \gset
insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by)
values(:'clinic',:'booklet_patient','soap','{"notes":"Synthetic confidential note"}','00000000-0000-0000-0000-000000000150');
insert into public.preventive_evidence(clinic_id,patient_id,event_id,label,mime,content,operation,created_by)
values(:'clinic',:'booklet_patient',:'booklet_event','Synthetic carnet proof','application/pdf',convert_to('%PDF-1.4 synthetic','UTF8'),repeat('a',48),'00000000-0000-0000-0000-000000000150');
insert into public.preventive_plans(clinic_id,patient_id,event_id,type,coverage,due_date,reason,operation,created_by)
values(:'clinic',:'booklet_patient',:'booklet_event','vacuna','Synthetic coverage','2027-10-20','Synthetic follow-up',repeat('b',48),'00000000-0000-0000-0000-000000000150') returning id as booklet_plan \gset
alter table public.preventive_plan_retirements disable trigger booklet_plan_lock;
insert into public.preventive_plan_retirements(plan_id,clinic_id,patient_id,reason,operation,created_by)
values(:'booklet_plan',:'clinic',:'booklet_patient','Synthetic correction',repeat('c',48),'00000000-0000-0000-0000-000000000150');
alter table public.preventive_plan_retirements enable trigger booklet_plan_lock;
insert into public.clinic_appointments(clinic_id,patient_id,patient_name,species,kind,professional_id,starts_at,ends_at,created_by)
values(:'clinic',:'booklet_patient','Synthetic booklet patient','canino','consulta','00000000-0000-0000-0000-000000000151','2030-01-01T10:00:00Z','2030-01-01T11:00:00Z','00000000-0000-0000-0000-000000000150')
returning id as booklet_appointment \gset
alter table public.preventive_appointment_links disable trigger booklet_plan_lock;
insert into public.preventive_appointment_links(plan_id,appointment_id,clinic_id,patient_id,operation,request,created_by)
values(:'booklet_plan',:'booklet_appointment',:'clinic',:'booklet_patient',repeat('d',48),'{}','00000000-0000-0000-0000-000000000150');
alter table public.preventive_appointment_links enable trigger booklet_plan_lock;

-- A visual administrator receives nothing automatically.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'backup_export_required');
select pg_temp.assert_true(not(public.backup_workspace(:'clinic')->'exports'->>'clinic')::boolean,'visual role opened clinic backup');
reset role;

-- The responsible grants explicit export and workspace administration.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','backup.export',null,clock_timestamp()+interval '1 day','Synthetic backup export') as export_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'backup_export_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic workspace authority') as manage_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','patient.read',null,clock_timestamp()+interval '1 day','Synthetic patient lookup') as patient_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true(exists(select 1 from pg_constraint where conrelid='public.clinic_appointments'::regclass and pg_get_constraintdef(oid) like '%cirugia%'),'additional appointment kinds missing');
select pg_temp.assert_true(jsonb_array_length(public.ops_patient_search(:'clinic','5550101'))=1 and public.ops_patient_search(:'clinic','5550101')->0->>'owner_name'='Synthetic booklet owner' and public.ops_patient_search(:'clinic','5550101')->0->>'owner_phone'='5550101','tutor phone lookup missing');
select pg_temp.assert_true(public.ops_patient_search(:'clinic','Synthetic confidential note')='[]'::jsonb,'clinical note matched without clinical.read');
select pg_temp.assert_true((public.backup_workspace(:'clinic')->'exports'->>'clinic')::boolean,'explicit clinic backup absent');
select pg_temp.assert_true((public.clinic_export(:'clinic')::jsonb->>'format')='vetdosis-operational-backup','clinic backup format mismatch');
select pg_temp.assert_true((public.clinic_export(:'clinic')::jsonb->'tables') ?& array['preventive_evidence','preventive_plans','preventive_plan_retirements','preventive_appointment_links'],'preventive booklet records missing from clinic backup');
select pg_temp.assert_true(jsonb_array_length(public.clinic_export(:'clinic')::jsonb->'tables'->'preventive_evidence')=1 and jsonb_array_length(public.clinic_export(:'clinic')::jsonb->'tables'->'preventive_plans')=1 and jsonb_array_length(public.clinic_export(:'clinic')::jsonb->'tables'->'preventive_plan_retirements')=1 and jsonb_array_length(public.clinic_export(:'clinic')::jsonb->'tables'->'preventive_appointment_links')=1,'preventive booklet rows were not preserved');
select pg_temp.assert_true(not(public.backup_workspace(:'clinic')->>'statistics')::boolean,'backup permissions leaked statistics');
select pg_temp.expect_error(format('select public.clinic_statistics(%L)',:'clinic'),'sales_read_required');
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','clinical.read',null,clock_timestamp()+interval '1 day','Synthetic authorized note search');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.ops_patient_search(:'clinic','Synthetic confidential note'))=1 and public.ops_patient_search(:'clinic','Synthetic confidential note')->0->>'clinical_match'='true','authorized clinical note lookup missing');
reset role;

-- Statistics remain a separate read capability.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','sales.read',null,clock_timestamp()+interval '1 day','Synthetic statistics read');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true((public.backup_workspace(:'clinic')->>'statistics')::boolean,'sales read did not open statistics');
select pg_temp.assert_true(public.clinic_statistics(:'clinic') ? 'sales','statistics payload missing');
select pg_temp.assert_true(public.clinic_statistics(:'clinic')->'species'='null'::jsonb,'sales grant exposed agenda aggregates');
select pg_temp.assert_true(public.clinic_statistics(:'clinic')->'low_stock'='null'::jsonb,'sales grant exposed inventory');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','appointment.read',null,clock_timestamp()+interval '1 day','Synthetic agenda summary');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','inventory.read',null,clock_timestamp()+interval '1 day','Synthetic stock summary');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true(jsonb_typeof(public.clinic_statistics(:'clinic')->'species')='array','agenda read did not open aggregate');
select pg_temp.assert_true(jsonb_typeof(public.clinic_statistics(:'clinic')->'low_stock')='array','inventory read did not open aggregate');
reset role;

-- A personal export belongs only to its owner and contains an allowlist.
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000181','synthetic-personal-owner@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select public.personal_workspace_create() as personal \gset
reset role;
insert into public.dose_personal_entries(clinic_id,user_id,payload,state) values(:'personal','00000000-0000-0000-0000-000000000181','{"source":"synthetic"}','personal');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select public.personal_export(:'personal')::jsonb as personal_backup \gset
select pg_temp.assert_true((:'personal_backup'::jsonb->>'format')='vetdosis-personal-backup','personal format mismatch');
select pg_temp.assert_true(jsonb_array_length(:'personal_backup'::jsonb->'tables'->'dose_personal_entries')=1,'own dose absent');
select pg_temp.assert_true(not(:'personal_backup'::jsonb->'tables' ?| array['vet_patients','vet_owners','clinical_cases','hospital_stays','form_documents','form_signatures']),'personal backup exposed clinical tables');
select pg_temp.assert_true((public.backup_workspace(:'personal')->'exports'->>'personal')::boolean and not(public.backup_workspace(:'personal')->'exports'->>'clinic')::boolean,'personal scopes mismatch');
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.expect_error(format('select public.personal_export(%L)',:'personal'),'personal_owner_required');reset role;
set role anon;
select pg_temp.expect_error(format('select public.backup_workspace(%L)',:'clinic'),'permission denied');
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'permission denied');reset role;

-- Revocation closes navigation and export on the next server call.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'export_grant','Synthetic backup revocation');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true(not(public.app_module_workspace(:'clinic')->'modules'->>'backup')::boolean,'revoked backup remained in navigation');
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'backup_export_required');reset role;
