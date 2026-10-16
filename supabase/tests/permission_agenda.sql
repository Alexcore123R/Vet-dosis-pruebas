-- Synthetic cases only, against complete M13/M14 + agenda + permission dependencies.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000080','agenda-admin@example.test',now()),
 ('00000000-0000-0000-0000-000000000081','agenda-manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000082','agenda-reader@example.test',now()),
 ('00000000-0000-0000-0000-000000000083','agenda-other@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000080',false);
select public.create_clinic('Synthetic agenda A') as clinic \gset
select set_config('test.agenda',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000081','auxiliar'),(:'clinic','00000000-0000-0000-0000-000000000082','mvz');
insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(:'clinic','Synthetic linked patient','synthetic','sin especificar',auth.uid()) returning id as patient \gset
select set_config('test.patient',:'patient',false);
insert into public.clinic_services(clinic_id,name,price,commission_kind,commission_value) values(:'clinic','Synthetic private prices',999,'porcentaje',30) returning id as service \gset
insert into public.clinic_messages(clinic_id,category,body,author_id) values(:'clinic','general','Synthetic private team message',auth.uid());
insert into public.clinic_tasks(clinic_id,title,priority,created_by) values(:'clinic','Synthetic private task','media',auth.uid());
insert into public.clinic_suppliers(clinic_id,name,created_by) values(:'clinic','Synthetic private supplier',auth.uid());
insert into public.clinic_service_acts(clinic_id,service_id,professional_id,name,service_version,price,commission,commission_kind,commission_value,created_by) values(:'clinic',:'service',auth.uid(),'Synthetic private act',1,999,299.70,'porcentaje',30,auth.uid());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000083',false);
select public.create_clinic('Synthetic agenda B') as other \gset
select set_config('test.other_agenda',:'other',false);
-- Admin role alone must not expose aggregated data or authorize agenda writes.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000080',false);
set role authenticated;
select pg_temp.assert_true(public.ops_dashboard(:'clinic')->'appointments'='[]','role exposed agenda');
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'appointment','{}',repeat('a',48))$q$,'explicit_permission_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000081','appointment.manage',null,now()+interval '1 day','Synthetic manage') as manage \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000082','appointment.read',null,now()+interval '1 day','Synthetic read') as read_grant \gset
select public.permission_set_job(:'clinic','00000000-0000-0000-0000-000000000081','MVZ');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',false);
set role authenticated;
select pg_temp.expect_error($q$select public.ops_patient_search(current_setting('test.agenda')::uuid,'Synthetic')$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'appointment',jsonb_build_object('patient_id',current_setting('test.patient')),repeat('b',48))$q$,'explicit_permission_required');
-- Management does not imply reading. Booking is administrative, not professional habilitation.
select public.ops_write(:'clinic','appointment',jsonb_build_object('patient_name','Synthetic walk-in','species','synthetic','kind','consulta','professional_id','00000000-0000-0000-0000-000000000082','starts_at','2030-01-01T12:00:00Z','ends_at','2030-01-01T13:00:00Z'),repeat('c',48)) as appointment \gset
select set_config('test.appointment',:'appointment',false);
select pg_temp.assert_true(public.ops_dashboard(:'clinic')->'appointments'='[]','manage implied read');
select pg_temp.expect_error($q$select public.ops_write_before_plans(current_setting('test.agenda')::uuid,'appointment','{}',repeat('d',48))$q$,'permission denied');
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'task','{"title":"Synthetic","priority":"media"}',repeat('e',48))$q$,'clinic_plan_required');
reset role;
select pg_temp.assert_true(not private.professional_current(:'clinic',auth.uid()),'booking or label verified professional');
select pg_temp.assert_true(exists(select 1 from public.audit_log where action='ops_appointment' and entity_id=:'appointment' and details->>'permission_grant_id'=:'manage'),'audit lost grant');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',false);
set role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.ops_dashboard(:'clinic')->'appointments')=1,'reader missing agenda');
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'appointment_state',jsonb_build_object('id',current_setting('test.appointment'),'version',1,'state','en_atencion'),repeat('f',48))$q$,'explicit_permission_required');
select pg_temp.assert_true(public.ops_dashboard(:'clinic')->'services'='[]' and public.ops_dashboard(:'clinic')->'acts'='[]' and public.ops_dashboard(:'clinic')->'suppliers'='[]' and public.ops_dashboard(:'clinic')->'messages'='[]' and public.ops_dashboard(:'clinic')->'tasks'='[]','aggregate leaked other areas');
select pg_temp.expect_error('select * from public.clinic_appointments','permission denied');
reset role;
-- Patient linking requires its own read permission, even for an idempotent retry.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000080',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000081','patient.read',null,now()+interval '1 day','Synthetic linkage') as patient_read \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',false);
set role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.ops_patient_search(:'clinic','Synthetic'))=1,'patient lookup missing');
select public.ops_write(:'clinic','appointment',jsonb_build_object('patient_id',:'patient','kind','consulta','professional_id','00000000-0000-0000-0000-000000000082','starts_at','2030-01-02T12:00:00Z','ends_at','2030-01-02T13:00:00Z'),repeat('1',48)) as linked \gset
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'appointment_reschedule',jsonb_build_object('id',current_setting('test.appointment'),'reason','Synthetic reason','starts_at','2030-01-03T12:00:00Z','ends_at','2030-01-03T13:00:00Z'),repeat('2',48))$q$,'version_conflict');
select public.ops_write(:'clinic','appointment_reschedule',jsonb_build_object('id',:'appointment','version',1,'reason','Synthetic reason','starts_at','2030-01-03T12:00:00Z','ends_at','2030-01-03T13:00:00Z'),repeat('3',48));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',false);
set role authenticated;
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.ops_dashboard(current_setting('test.agenda')::uuid)->'appointments') a where a->>'patient_id' is not null),'patient record link exposed without patient.read');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000080',false);
set role authenticated;
select public.permission_revoke(:'patient_read','Synthetic revoke linkage');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',false);
set role authenticated;
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'appointment',jsonb_build_object('patient_id',current_setting('test.patient'),'kind','consulta','professional_id','00000000-0000-0000-0000-000000000082','starts_at','2030-01-02T12:00:00Z','ends_at','2030-01-02T13:00:00Z'),repeat('1',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000080',false);
set role authenticated;
select public.permission_revoke(:'manage','Synthetic revoke');
select public.permission_revoke(:'read_grant','Synthetic revoke');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',false);
set role authenticated;
select pg_temp.expect_error($q$select public.ops_write(current_setting('test.agenda')::uuid,'appointment',jsonb_build_object('patient_name','Synthetic walk-in','species','synthetic','kind','consulta','professional_id','00000000-0000-0000-0000-000000000082','starts_at','2030-01-01T12:00:00Z','ends_at','2030-01-01T13:00:00Z'),repeat('c',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',false);
set role authenticated;
select pg_temp.assert_true(public.ops_dashboard(:'clinic')->'appointments'='[]','revoked read survived');
select pg_temp.expect_error($q$select public.ops_dashboard(current_setting('test.other_agenda')::uuid)$q$,'access_denied');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.ops_dashboard(null)$q$,'permission denied');
select pg_temp.expect_error($q$select public.ops_write(null,'appointment','{}',repeat('4',48))$q$,'permission denied');
reset role;
select pg_temp.assert_true(not(select enforcement_enabled or migration_reviewed from private.permission_policy),'global cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
