-- Synthetic review orders only: no clinical norms, medication or real professional evidence.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000140','reviews-admin@example.test',now()),
 ('00000000-0000-0000-0000-000000000141','reviews-professional@example.test',now()),
 ('00000000-0000-0000-0000-000000000142','reviews-member@example.test',now()),
 ('00000000-0000-0000-0000-000000000143','reviews-other@example.test',now()),
 ('00000000-0000-0000-0000-000000000144','reviews-platform@example.test',now());
insert into private.platform_admins(user_id) values('00000000-0000-0000-0000-000000000144');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000140',false);
select public.create_clinic('Synthetic reviews clinic') as clinic \gset
select set_config('test.clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000141','mvz'),(:'clinic','00000000-0000-0000-0000-000000000142','auxiliar');
insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(:'clinic','Synthetic review patient','synthetic','sin especificar',auth.uid()) returning id as patient \gset
insert into public.hospital_stays(clinic_id,patient_id,admitted_by) values(:'clinic',:'patient',auth.uid()) returning id as stay \gset
select set_config('test.stay',:'stay',false);
insert into private.procedure_types(clinic_id,name,created_by) values(:'clinic','Synthetic review type',auth.uid()) returning id as procedure \gset
select set_config('test.procedure',:'procedure',false);
insert into private.procedure_types(clinic_id,name,created_by) values(:'clinic','Synthetic other type',auth.uid()) returning id as other_type \gset
select set_config('test.times',jsonb_build_array(to_char(clock_timestamp()+interval '1 hour','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_review_schedule(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,current_setting('test.procedure')::uuid,'Synthetic review','Synthetic instructions',current_setting('test.times')::jsonb,15,repeat('a',48))$q$,'explicit_permission_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000141','hospital.read',null,now()+interval '1 day','Synthetic read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000142','hospital.read',null,now()+interval '1 day','Synthetic read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000142','hospital.report',null,now()+interval '1 day','Synthetic postpone');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000141','procedure.perform',:'other_type',now()+interval '1 day','Synthetic wrong procedure');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000142','procedure.perform',:'procedure',now()+interval '1 day','Synthetic grant without professional evidence');
reset role;
-- Professional evidence does not itself grant the ability to schedule.
insert into public.professional_profiles(clinic_id,user_id) values(:'clinic','00000000-0000-0000-0000-000000000141') returning id as profile \gset
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'profile',1,'Synthetic reviewer','SYNTHETIC-REVIEWS','00000000-0000-0000-0000-000000000141') returning id as profile_version \gset
select private.professional_record_external(:'profile_version','00000000-0000-0000-0000-000000000144',clock_timestamp(),repeat('b',64),'Synthetic evidence only',clock_timestamp()+interval '1 day') as verification \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_review_schedule(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,current_setting('test.procedure')::uuid,'Synthetic review','Synthetic instructions',current_setting('test.times')::jsonb,15,repeat('a',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000140',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000141','hospital.schedule',null,now()+interval '1 day','Synthetic scheduling') as schedule_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select public.hospital_review_schedule(:'clinic',:'stay',:'procedure','Synthetic review','Synthetic instructions',current_setting('test.times')::jsonb,15,repeat('a',48)) as task \gset
select public.hospital_review_schedule(:'clinic',:'stay',:'procedure','Synthetic review','Synthetic instructions',current_setting('test.times')::jsonb,15,repeat('a',48)) as retry \gset
select pg_temp.assert_true(:'task'=:'retry','schedule retry duplicated');
select set_config('test.task',:'task',false);
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'capabilities'->>'typed_reviews')::boolean,'typed capability missing');
select pg_temp.assert_true(jsonb_array_length(public.hospital_snapshot(:'clinic')->'review_types')=2,'active types unavailable');
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'permissions'->>'hospital.schedule')::boolean,'schedule permission missing');
select pg_temp.assert_true(not (public.hospital_snapshot(:'clinic')->'permissions'->>'hospital.discharge')::boolean,'unmigrated discharge advertised');
select pg_temp.assert_true(not (public.hospital_snapshot(:'clinic')->'tasks'->0->'actions'->>'perform')::boolean,'wrong-type authority advertised');
select pg_temp.expect_error('select private.hospital_snapshot_before_reviews(null)','permission denied');
select pg_temp.expect_error($q$select public.hospital_review_schedule(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,null,'Synthetic','Synthetic',current_setting('test.times')::jsonb,15,repeat('b',48))$q$,'active_procedure_required');
select pg_temp.expect_error($q$select public.hospital_review_schedule(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,current_setting('test.procedure')::uuid,'Synthetic','Synthetic','[]',15,repeat('b',48))$q$,'invalid_times');
select pg_temp.expect_error($q$select public.hospital_review_schedule(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,current_setting('test.procedure')::uuid,'Synthetic','Synthetic',jsonb_build_array('2000-01-01T00:00:00Z'),15,repeat('b',48))$q$,'past_order_time');
select pg_temp.expect_error($q$select public.hospital_prescribe(null,null,'medicacion','x','x','[]',15,repeat('c',48))$q$,'structured_medication_order_required');
select pg_temp.expect_error($q$select public.hospital_prescribe(null,null,'revision','x','x','[]',15,repeat('c',48))$q$,'typed_review_order_required');
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'perform')$q$,'explicit_permission_required');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.hospital_tasks where clinic_id=:'clinic'),'schedule duplicated or partially inserted');
select pg_temp.assert_true((select procedure_type_id=:'procedure' and authority_grant_id=:'schedule_grant' from public.hospital_tasks where id=:'task'),'missing authority binding');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000140',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000141','procedure.perform',:'procedure',now()+interval '1 day','Synthetic exact procedure') as perform_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'perform')$q$,'task_not_due');
reset role;
-- Set due in fixture only, not a client edit or a default clinical interval.
update public.hospital_tasks set due_at=clock_timestamp()-interval '1 minute' where id=:'task';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000142',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'perform')$q$,'verified_professional_required');
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'snooze',10,'')$q$,'invalid_snooze');
select public.hospital_task_action(:'clinic',:'task',1,'snooze',10,'Synthetic postponement');
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,1,'snooze',10,'Synthetic')$q$,'version_conflict');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,2,'perform')$q$,'task_not_due');
reset role;
update public.hospital_tasks set snoozed_until=clock_timestamp()-interval '1 second' where id=:'task';
set role authenticated;
select public.hospital_task_action(:'clinic',:'task',2,'perform');
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,2,'perform')$q$,'task_already_confirmed');
reset role;
select pg_temp.assert_true((select state='done' and version=3 and performed_by='00000000-0000-0000-0000-000000000141' and performed_at is not null from public.hospital_tasks where id=:'task'),'incorrect confirmation');
select pg_temp.assert_true((select count(*)=1 from public.audit_log where entity_id=:'task' and action='hospital_task_perform' and details->>'permission_grant_id'=:'perform_grant'),'duplicate or missing confirmation audit');
-- Historical reviews remain visible, without guessed authority; text medication cannot use this action.
insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by) values(:'clinic',:'stay','revision','Synthetic historical','Synthetic',clock_timestamp()-interval '1 minute',15,auth.uid()) returning id as legacy \gset
select set_config('test.legacy',:'legacy',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.legacy')::uuid,1,'perform')$q$,'legacy_review_reauthorization_required');
reset role;
insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by) values(:'clinic',:'stay','medicacion','Synthetic historical medication','Synthetic',clock_timestamp()-interval '1 minute',15,auth.uid()) returning id as medication \gset
select set_config('test.medication',:'medication',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.medication')::uuid,1,'perform')$q$,'structured_medication_action_required');
-- Schedule authority can cancel a review, with reason, but report-only cannot.
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000142',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.legacy')::uuid,1,'cancel',null,'Synthetic')$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.legacy')::uuid,1,'cancel',null,'')$q$,'reason_required');
select public.hospital_task_action(:'clinic',:'legacy',1,'cancel',null,'Synthetic cancellation');
reset role;
-- Revoking schedule authority also blocks an otherwise idempotent schedule retry.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000140',false);
set role authenticated;
select public.permission_revoke(:'schedule_grant','Synthetic revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_review_schedule(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,current_setting('test.procedure')::uuid,'Synthetic review','Synthetic instructions',current_setting('test.times')::jsonb,15,repeat('a',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000143',false);
select public.create_clinic('Synthetic reviews other clinic');
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_task_action(current_setting('test.clinic')::uuid,current_setting('test.task')::uuid,3,'perform')$q$,'explicit_permission_required');
reset role;
set role anon;
select pg_temp.expect_error('select public.hospital_review_schedule(null,null,null,null,null,null,null,null)','permission denied');
select pg_temp.expect_error('select public.hospital_task_action(null,null,null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
