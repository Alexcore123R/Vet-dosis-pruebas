-- Isolated synthetic records; no professional approval or patient data for real accounts.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000110','clinical-admin@example.test',now()),
 ('00000000-0000-0000-0000-000000000111','clinical-professional@example.test',now()),
 ('00000000-0000-0000-0000-000000000112','clinical-observer@example.test',now()),
 ('00000000-0000-0000-0000-000000000113','clinical-other@example.test',now()),
 ('00000000-0000-0000-0000-000000000114','clinical-platform@example.test',now());
insert into private.platform_admins(user_id) values('00000000-0000-0000-0000-000000000114');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
select public.create_clinic('Synthetic clinical permission A') as clinic \gset
select set_config('test.clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000111','mvz'),(:'clinic','00000000-0000-0000-0000-000000000112','auxiliar');
insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(:'clinic','Synthetic clinical patient','synthetic','sin especificar',auth.uid()) returning id as patient \gset
insert into public.form_templates(clinic_id,created_by) values(:'clinic',auth.uid()) returning id as template \gset
insert into public.form_template_versions(template_id,clinic_id,version,schema,reason,created_by) values(:'template',:'clinic',1,'{"type":"clinical_history"}','Synthetic fixture',auth.uid()) returning id as version \gset
insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by) values(:'clinic',:'patient',:'version','00000000-0000-0000-0000-000000000111','{}','{}','{}',auth.uid()) returning id as doc \gset
insert into public.clinical_cases(clinic_id,patient_id,document_id,responsible_id,kind,title,reason,clinical_date) values(:'clinic',:'patient',:'doc','00000000-0000-0000-0000-000000000111','clinical_history','Synthetic case','Synthetic reason',current_date) returning id as case_id \gset
select set_config('test.case',:'case_id',false);
insert into public.case_staff_assignments(clinic_id,case_id,person_id,role) values(:'clinic',:'case_id','00000000-0000-0000-0000-000000000111','responsable');
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_case_snapshot(current_setting('test.case')::uuid)$q$,'clinical_access_denied');
select pg_temp.expect_error($q$select public.permission_grant(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000111','clinical.authorize',null,now()+interval '1 day','Synthetic')$q$,'verified_professional_required');
select public.permission_procedure_set(:'clinic',null,'Synthetic observation type',true) as procedure \gset
select public.permission_procedure_set(:'clinic',null,'Synthetic other type',true) as other_procedure \gset
select public.permission_set_job(:'clinic','00000000-0000-0000-0000-000000000112','MVZ');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000111','clinical.read',null,now()+interval '1 day','Synthetic read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000111','patient.read',null,now()+interval '1 day','Synthetic read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000112','patient.read',null,now()+interval '1 day','Synthetic administrative read');
reset role;
insert into public.professional_profiles(clinic_id,user_id) values(:'clinic','00000000-0000-0000-0000-000000000111') returning id as profile \gset
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'profile',1,'Synthetic professional','SYNTHETIC-ONLY','00000000-0000-0000-0000-000000000111') returning id as profile_version \gset
select private.professional_record_external(:'profile_version','00000000-0000-0000-0000-000000000114',clock_timestamp(),repeat('a',64),'Synthetic evidence only',clock_timestamp()+interval '1 day') as verification \gset
select set_config('test.verification',:'verification',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_scope_bind(current_setting('test.case')::uuid,'observaciones',null,false,'Synthetic','Synthetic')$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000111','clinical.authorize',null,now()+interval '1 day','Synthetic authority');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000112','clinical.read',null,now()+interval '1 day','Synthetic clinical read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000112','procedure.perform',:'other_procedure',now()+interval '1 day','Synthetic wrong type');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select public.clinical_scope_bind(:'case_id','observaciones',:'procedure',false,'Synthetic policy for testing only','Initial synthetic binding') as binding \gset
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000112','observaciones',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('a',48));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',false);
set role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.clinical_cases_list(:'clinic'))=1,'explicit reader denied');
select pg_temp.expect_error($q$select public.clinical_observation_add(current_setting('test.case')::uuid,jsonb_build_object('kind','weight','value','4','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('b',48))$q$,'explicit_procedure_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000112','procedure.perform',:'procedure',now()+interval '1 day','Synthetic observation') as grant_id \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',false);
set role authenticated;
select set_config('test.data',jsonb_build_object('kind','weight','value','4','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,false);
select public.clinical_observation_add(:'case_id',current_setting('test.data')::jsonb,repeat('c',48)) as observation \gset
select public.clinical_observation_add(:'case_id',current_setting('test.data')::jsonb,repeat('c',48)) as retry \gset
select pg_temp.assert_true(:'observation'=:'retry','retry duplicated observation');
select pg_temp.expect_error($q$select public.clinical_observation_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||jsonb_build_object('performed_by','00000000-0000-0000-0000-000000000111'),repeat('d',48))$q$,'own_act_only');
select pg_temp.expect_error($q$select public.add_vet_patient_event(current_setting('test.clinic')::uuid,null,'weight','{}',repeat('e',48))$q$,'structured_clinical_record_required');
reset role;
-- A legacy case authorization is retained but cannot replace reviewed metadata.
insert into public.person_procedure_authorizations(clinic_id,case_id,person_id,scope,valid_until,granted_by)
values(:'clinic',:'case_id','00000000-0000-0000-0000-000000000112','observaciones',clock_timestamp()+interval '1 day','00000000-0000-0000-0000-000000000110');
insert into public.person_procedure_revocations(authorization_id,reason,created_by)
select id,'Synthetic revoke new-model case authorization','00000000-0000-0000-0000-000000000111'
from public.person_procedure_authorizations where case_id=:'case_id' and person_id='00000000-0000-0000-0000-000000000112' and authority_grant_id is not null;
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_observation_add(current_setting('test.case')::uuid,jsonb_build_object('kind','weight','value','4','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('4',48))$q$,'case_authorization_required');
reset role;
select pg_temp.assert_true(exists(select 1 from public.audit_log where entity_id=:'observation' and details->>'permission_grant_id'=:'grant_id' and details->>'binding_id'=:'binding'),'lost grant/binding audit');
select pg_temp.expect_error($q$update public.clinical_observations set value=99 where id=(select id from public.clinical_observations limit 1)$q$,'clinical_record_is_immutable_append_correction');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select public.clinical_authorize(:'case_id',auth.uid(),'observaciones',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('7',48));
select pg_temp.expect_error($q$select public.clinical_observation_add(current_setting('test.case')::uuid,jsonb_build_object('kind','weight','value','4','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('8',48))$q$,'explicit_procedure_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000111','procedure.perform',:'procedure',now()+interval '1 day','Synthetic correction');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select public.clinical_observation_add(:'case_id',jsonb_build_object('kind','weight','value','4.5','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'replaces_id',:'observation','correction_reason','Synthetic correction'),repeat('9',48));
reset role;
select pg_temp.assert_true((select count(*)=2 from public.clinical_observations where case_id=:'case_id'),'correction did not append');
select pg_temp.assert_true((select value=4 from public.clinical_observations where id=:'observation'),'correction rewrote original');
set role authenticated;
select public.clinical_scope_bind(:'case_id','observaciones',:'procedure',true,'Synthetic stricter policy','Synthetic replacement');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',false);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_observation_add(current_setting('test.case')::uuid,jsonb_build_object('kind','weight','value','4','unit','kg','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('f',48))$q$,'verified_professional_required');
reset role;
select pg_temp.assert_true((select count(*)=1 from private.clinical_scope_revocations where binding_id=:'binding'),'binding history not preserved');
select pg_temp.expect_error('update private.clinical_scope_bindings set professional_required=false','append_only_permission_record');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select public.clinical_scope_bind(:'case_id','cuidados',:'other_procedure',true,'Synthetic professional act policy','Initial synthetic binding');
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000112','cuidados',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('5',48));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',false);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_act_add(current_setting('test.case')::uuid,'cuidados','Synthetic act',auth.uid(),to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('6',48))$q$,'verified_professional_required');
reset role;
-- Professional verification revocation prevents authority despite an unexpired grant.
insert into private.professional_revocations(verification_id,revoked_by,reason) values(:'verification','00000000-0000-0000-0000-000000000114','Synthetic revocation');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_scope_bind(current_setting('test.case')::uuid,'observaciones',null,false,'Synthetic','Synthetic')$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000113',false);
select public.create_clinic('Synthetic clinical permission B') as other \gset
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_case_snapshot(current_setting('test.case')::uuid)$q$,'clinical_access_denied');
select pg_temp.expect_error('select * from private.clinical_scope_bindings','permission denied');
reset role;
set role anon;
select pg_temp.expect_error('select public.clinical_cases_list(null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'global cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
