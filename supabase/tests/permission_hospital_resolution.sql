-- Continues the synthetic 13F fixture; no clinical defaults or real patient data.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id,patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select id as procedure from private.procedure_types where clinic_id=:'clinic' and name='Synthetic medication care' \gset
select id as other_type from private.procedure_types where clinic_id=:'clinic' and name='Synthetic unrelated type' \gset
select id as stay from public.hospital_stays where clinic_id=:'clinic' \gset
select id as product from public.medication_product_versions where product_key='synthetic-permission-liquid' \gset
select set_config('test.clinic',:'clinic',false);select set_config('test.stay',:'stay',false);select set_config('test.case',:'case_id',false);
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000160','followup@example.test',now()),('00000000-0000-0000-0000-000000000161','wrong-followup@example.test',now()),('00000000-0000-0000-0000-000000000163','unverified-discharge@example.test',now());
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000160','auxiliar'),(:'clinic','00000000-0000-0000-0000-000000000161','auxiliar'),(:'clinic','00000000-0000-0000-0000-000000000163','mvz');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000160','hospital.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000161','hospital.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000160','medication.followup',:'procedure',now()+interval '1 day','Synthetic followup') as followup_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000161','medication.followup',:'other_type',now()+interval '1 day','Synthetic wrong type');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','vial.draw',:'procedure',now()+interval '1 day','Synthetic restored draw');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','hospital.read',null,now()+interval '1 day','Synthetic');
select pg_temp.expect_error(format('select public.permission_grant(%L,''00000000-0000-0000-0000-000000000163'',''hospital.discharge'',null,now()+interval ''1 day'',''Synthetic'')',:'clinic'),'verified_professional_required');
select pg_temp.expect_error($q$select public.hospital_discharge_preview(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid)$q$,'explicit_permission_required');
reset role;
insert into public.medication_vials(id,clinic_id,product_version_id,lot,initial_volume,unit,responsible_id,opened_at) values('00000000-0000-0000-0000-000000000410',:'clinic',:'product','SYNTHETIC-RESOLUTION',10,'ml','00000000-0000-0000-0000-000000000151',clock_timestamp()-interval '2 minutes');
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,prescription_item_id,clinical_case_id,procedure_type_id,authority_grant_id)
select x.id,t.clinic_id,t.stay_id,t.kind,'Synthetic resolution '||x.id::text,'Synthetic',case when x.future then clock_timestamp()+interval '1 day' else clock_timestamp()-interval '1 minute' end,15,t.created_by,t.prescription_item_id,t.clinical_case_id,t.procedure_type_id,t.authority_grant_id from public.hospital_tasks t
cross join (values('00000000-0000-0000-0000-000000000400'::uuid,false),('00000000-0000-0000-0000-000000000401'::uuid,false),('00000000-0000-0000-0000-000000000402'::uuid,false),('00000000-0000-0000-0000-000000000403'::uuid,false),('00000000-0000-0000-0000-000000000404'::uuid,true)) x(id,future)
where t.clinic_id=:'clinic';
select due_at::text as original_due from public.hospital_tasks where id='00000000-0000-0000-0000-000000000400' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_medication_followup(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000400',1,'not_given',null,'Synthetic',repeat('a1',24))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);
set role authenticated;
select pg_temp.assert_true(not (select (t->'actions'->>'perform')::boolean from jsonb_array_elements(public.hospital_snapshot(:'clinic')->'tasks') t where t->>'id'='00000000-0000-0000-0000-000000000400'),'followup granted administration');
select pg_temp.assert_true((select (t->'actions'->>'not_given')::boolean from jsonb_array_elements(public.hospital_snapshot(:'clinic')->'tasks') t where t->>'id'='00000000-0000-0000-0000-000000000400'),'followup unavailable');
select pg_temp.expect_error($q$select public.hospital_medication_followup(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000400',1,'not_given',null,'',repeat('a1',24))$q$,'followup_action_and_reason_required');
select pg_temp.expect_error($q$select public.hospital_medication_followup(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000404',1,'not_given',null,'Synthetic',repeat('a1',24))$q$,'task_not_due');
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000400',1,'snooze',10,'Synthetic delay',repeat('a1',24)) as snooze_event \gset
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000400',1,'snooze',10,'Synthetic delay',repeat('a1',24));
select pg_temp.expect_error($q$select public.hospital_medication_followup(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000400',1,'not_given',null,'Synthetic',repeat('a2',24))$q$,'task_version_conflict');
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000400',2,'not_given',null,'Synthetic absence',repeat('a2',24)) as not_given_event \gset
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000400',2,'not_given',null,'Synthetic absence',repeat('a2',24));
reset role;
select pg_temp.assert_true((select state='cancelled' and resolution_kind='not_given' and cancelled_by='00000000-0000-0000-0000-000000000160' and cancelled_at is not null and performed_by is null and medication_record_id is null and due_at=:'original_due'::timestamptz and version=3 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000400'),'not-given implied application, duplicate or reschedule');
select pg_temp.assert_true(private.rx_vial_balance('00000000-0000-0000-0000-000000000410')=10,'followup consumed stock');
select pg_temp.assert_true((select details->>'permission_grant_id'=:'followup_grant' from public.audit_log where details->>'event_id'=:'not_given_event'),'followup authority lost');
select pg_temp.assert_true((select state='pending' from public.hospital_tasks where id='00000000-0000-0000-0000-000000000401'),'following task modified');
-- Restore no clinical roles: application still needs all 13F permissions independently.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
select set_config('test.application',jsonb_build_object('product_version_id',:'product','quantity','2','unit','ml','route','synthetic route','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id','00000000-0000-0000-0000-000000000410')::text,false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.application')::jsonb||jsonb_build_object('hospital_task_id','00000000-0000-0000-0000-000000000400','hospital_task_version',3),repeat('b1',24))$q$,'task_closed_without_application');
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.application')::jsonb||jsonb_build_object('hospital_task_id','00000000-0000-0000-0000-000000000401'),repeat('b1',24))$q$,'hospital_task_version_required');
select public.rx_medication_report(:'case_id',current_setting('test.application')::jsonb||jsonb_build_object('hospital_task_id','00000000-0000-0000-0000-000000000401','hospital_task_version',1),repeat('b1',24)) as application \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_medication_followup(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000401',1,'not_given',null,'Synthetic',repeat('a3',24))$q$,'task_already_confirmed');
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000402',1,'snooze',10,'Synthetic delay',repeat('a4',24));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.application')::jsonb||jsonb_build_object('hospital_task_id','00000000-0000-0000-0000-000000000402','hospital_task_version',1),repeat('b2',24))$q$,'task_version_conflict');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_discharge_preview(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid)$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.discharge',null,now()+interval '1 day','Synthetic discharge') as discharge_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select public.hospital_discharge_preview(:'clinic',:'stay') as preview \gset
select set_config('test.preview',:'preview',false);
select pg_temp.assert_true(jsonb_array_length(:'preview'::jsonb->'pending')=3,'preview omitted future pending tasks');
select pg_temp.expect_error($q$select public.hospital_discharge_confirm(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,(current_setting('test.preview')::jsonb->>'version')::int,current_setting('test.preview')::jsonb->>'pending_hash','',repeat('c1',24))$q$,'reviewed_discharge_reason_required');
select pg_temp.expect_error($q$select public.hospital_discharge(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,1,'Synthetic')$q$,'reviewed_discharge_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);
set role authenticated;
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000402',2,'snooze',10,'Synthetic changed pending',repeat('a5',24));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_discharge_confirm(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,(current_setting('test.preview')::jsonb->>'version')::int,current_setting('test.preview')::jsonb->>'pending_hash','Synthetic',repeat('c1',24))$q$,'discharge_preview_changed');
select public.hospital_discharge_preview(:'clinic',:'stay') as preview \gset
select set_config('test.preview',:'preview',false);
reset role;
update public.hospital_stays set version=version+1,cage='Synthetic moved' where id=:'stay';
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_discharge_confirm(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid,(current_setting('test.preview')::jsonb->>'version')::int,current_setting('test.preview')::jsonb->>'pending_hash','Synthetic',repeat('c1',24))$q$,'hospital_version_conflict');
select public.hospital_discharge_preview(:'clinic',:'stay') as final_preview \gset
select public.hospital_discharge_confirm(:'clinic',:'stay',(:'final_preview'::jsonb->>'version')::int,:'final_preview'::jsonb->>'pending_hash','Synthetic reviewed discharge',repeat('c1',24));
select public.hospital_discharge_confirm(:'clinic',:'stay',(:'final_preview'::jsonb->>'version')::int,:'final_preview'::jsonb->>'pending_hash','Synthetic reviewed discharge',repeat('c1',24));
reset role;
select pg_temp.assert_true(private.rx_vial_balance('00000000-0000-0000-0000-000000000410')=8,'discharge/omission changed stock');
select pg_temp.assert_true((select resolution_kind='not_given' from public.hospital_tasks where id='00000000-0000-0000-0000-000000000400'),'discharge rewrote omission');
select pg_temp.assert_true((select state='done' and medication_record_id=:'application' from public.hospital_tasks where id='00000000-0000-0000-0000-000000000401'),'discharge rewrote application');
select pg_temp.assert_true((select count(*)=3 from public.hospital_tasks where stay_id=:'stay' and resolution_kind='discharge'),'wrong discharge cancellations');
select pg_temp.assert_true((select count(*)=1 from public.audit_log where action='hospital_discharged' and entity_id=:'stay' and details->>'permission_grant_id'=:'discharge_grant'),'duplicate discharge or lost authority');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_revoke(:'followup_grant','Synthetic revoked followup');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_medication_followup(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000400',2,'not_given',null,'Synthetic absence',repeat('a2',24))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_discharge_preview(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid)$q$,'explicit_permission_required');
reset role;
set role anon;
select pg_temp.expect_error('select public.hospital_medication_followup(null,null,null,null,null,null,null)','permission denied');
select pg_temp.expect_error('select public.hospital_discharge_confirm(null,null,null,null,null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select enforcement_enabled or migration_reviewed from private.permission_policy),'cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
