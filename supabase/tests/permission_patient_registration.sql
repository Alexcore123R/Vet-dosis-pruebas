-- Synthetic patients/owners only. Do not apply this test to a project.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000050','patient-admin@example.test',now()),
 ('00000000-0000-0000-0000-000000000051','patient-staff@example.test',now()),
 ('00000000-0000-0000-0000-000000000052','patient-other@example.test',now()),
 ('00000000-0000-0000-0000-000000000053','patient-mvz@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000050',false);
select public.create_clinic('Synthetic patient permissions A') as clinic \gset
select set_config('test.patient_clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values
 (:'clinic','00000000-0000-0000-0000-000000000051','auxiliar'),
 (:'clinic','00000000-0000-0000-0000-000000000053','mvz');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000052',false);
select public.create_clinic('Synthetic patient permissions B') as other \gset
select set_config('test.patient_other',:'other',false);
-- Administrator and MVZ role confer no registration permission.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000050',false);
set role authenticated;
select pg_temp.expect_error($q$select public.create_vet_patient(current_setting('test.patient_clinic')::uuid,'{"name":"Synthetic","species":"synthetic","sex":"sin especificar"}',null,repeat('a',48))$q$,'explicit_permission_required');
select public.permission_set_job(:'clinic','00000000-0000-0000-0000-000000000051','MVZ');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000051','patient.write',null,now()+interval '1 day','Synthetic registration') as write_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000053','patient.read',null,now()+interval '1 day','Synthetic reader') as read_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000053',false);
set role authenticated;
select pg_temp.expect_error($q$select public.create_vet_patient(current_setting('test.patient_clinic')::uuid,'{"name":"Synthetic","species":"synthetic","sex":"sin especificar"}',null,repeat('b',48))$q$,'explicit_permission_required');
reset role;
-- Explicit demographic write works without inferring professional status or read access.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000051',false);
set role authenticated;
select public.create_vet_patient(:'clinic','{"name":"Synthetic","species":"synthetic","sex":"sin especificar"}','{"name":"Synthetic owner"}',repeat('c',48)) as patient \gset
select public.create_vet_patient(:'clinic','{"name":"Synthetic","species":"synthetic","sex":"sin especificar"}','{"name":"Synthetic owner"}',repeat('c',48)) as retry \gset
select pg_temp.assert_true(:'patient'=:'retry','retry duplicated patient');
select pg_temp.assert_true(not exists(select 1 from public.vet_patients where clinic_id=current_setting('test.patient_clinic')::uuid),'write implicitly granted read');
select pg_temp.assert_true(not exists(select 1 from public.vet_owners where clinic_id=current_setting('test.patient_clinic')::uuid),'write exposed owner contacts');
select pg_temp.expect_error($q$select public.create_vet_patient(current_setting('test.patient_clinic')::uuid,'{"name":"Changed","species":"synthetic","sex":"sin especificar"}',null,repeat('c',48))$q$,'operation_payload_changed');
select pg_temp.expect_error($q$select public.create_vet_patient(current_setting('test.patient_other')::uuid,'{"name":"Synthetic","species":"synthetic","sex":"sin especificar"}',null,repeat('d',48))$q$,'explicit_permission_required');
reset role;
select pg_temp.assert_true(not private.professional_current(:'clinic',auth.uid()),'registration or label conferred professional status');
select pg_temp.assert_true((select count(*)=1 from public.vet_patients where id=:'patient'),'wrong registration count');
select pg_temp.assert_true(exists(select 1 from public.audit_log where action='patient_created' and entity_id=:'patient' and actor_id=auth.uid() and details->>'permission_grant_id'=:'write_grant'),'audit lost exact grant or author');
-- RLS read follows explicit permission only; clinic administrator has no implicit read.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000050',false);
set role authenticated;
select pg_temp.assert_true(not exists(select 1 from public.vet_patients where clinic_id=current_setting('test.patient_clinic')::uuid),'admin role bypassed RLS');
select public.permission_revoke(:'write_grant','Synthetic revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000051',false);
set role authenticated;
select pg_temp.expect_error($q$select public.create_vet_patient(current_setting('test.patient_clinic')::uuid,'{"name":"Synthetic","species":"synthetic","sex":"sin especificar"}','{"name":"Synthetic owner"}',repeat('c',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000053',false);
set role authenticated;
select pg_temp.assert_true(exists(select 1 from public.vet_patients where id=:'patient'),'explicit patient reader blocked');
select pg_temp.assert_true(exists(select 1 from public.vet_owners where clinic_id=current_setting('test.patient_clinic')::uuid),'explicit owner reader blocked');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000052',false);
set role authenticated;
select pg_temp.assert_true(not exists(select 1 from public.vet_patients where id=:'patient'),'patient leaked across clinics');
select pg_temp.assert_true(not exists(select 1 from public.vet_owners where clinic_id=current_setting('test.patient_clinic')::uuid),'owner leaked across clinics');
reset role;
set role anon;
select pg_temp.expect_error('select * from public.vet_patients','permission denied');
select pg_temp.expect_error($q$select public.create_vet_patient(null,'{}',null,repeat('e',48))$q$,'permission denied');
reset role;
select pg_temp.assert_true(not(select enforcement_enabled or migration_reviewed from private.permission_policy),'global cutover activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
