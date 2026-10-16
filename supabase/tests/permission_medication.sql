-- Entirely synthetic. Never publishes clinical references or verifies a real professional.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000150','med-admin@example.test',now()),
 ('00000000-0000-0000-0000-000000000151','med-responsible@example.test',now()),
 ('00000000-0000-0000-0000-000000000152','med-performer@example.test',now()),
 ('00000000-0000-0000-0000-000000000153','med-other@example.test',now()),
 ('00000000-0000-0000-0000-000000000154','med-platform@example.test',now());
insert into private.platform_admins(user_id) values('00000000-0000-0000-0000-000000000154');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
select public.create_clinic('Synthetic medication permissions') as clinic \gset
select set_config('test.clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000151','mvz'),(:'clinic','00000000-0000-0000-0000-000000000152','auxiliar');
insert into public.vet_patients(clinic_id,name,species,sex,created_by) values(:'clinic','Synthetic medication patient','synthetic','sin especificar',auth.uid()) returning id as patient \gset
insert into public.form_templates(clinic_id,created_by) values(:'clinic',auth.uid()) returning id as template \gset
insert into public.form_template_versions(template_id,clinic_id,version,schema,reason,created_by) values(:'template',:'clinic',1,'{"type":"clinical_history"}','Synthetic fixture',auth.uid()) returning id as version \gset
insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by) values(:'clinic',:'patient',:'version','00000000-0000-0000-0000-000000000151','{}','{}','{}',auth.uid()) returning id as doc \gset
insert into public.clinical_cases(clinic_id,patient_id,document_id,responsible_id,kind,title,reason,clinical_date) values(:'clinic',:'patient',:'doc','00000000-0000-0000-0000-000000000151','clinical_history','Synthetic medication case','Synthetic',current_date-1) returning id as case_id \gset
select set_config('test.case',:'case_id',false);
insert into public.medication_product_versions(product_key,version,name,presentation,unit,classification,source,source_status) values('synthetic-permission-liquid',1,'Synthetic liquid','Synthetic only','ml','desconocida','{"reference":"Synthetic fixture; no clinical use"}','sin verificar') returning id as product \gset
select set_config('test.product',:'product',false);
insert into public.medication_product_versions(product_key,version,name,presentation,unit,classification,source,source_status) values('synthetic-permission-controlled',1,'Synthetic classified liquid','Synthetic only','ml','grupo_i','{"reference":"Synthetic fixture; no clinical use"}','sin verificar') returning id as controlled \gset
insert into public.professional_profiles(clinic_id,user_id) values(:'clinic','00000000-0000-0000-0000-000000000151'),(:'clinic','00000000-0000-0000-0000-000000000152');
insert into private.professional_profile_versions(profile_id,version,name,license,created_by)
select id,1,'Synthetic professional '||user_id::text,'SYNTHETIC-'||user_id::text,user_id from public.professional_profiles where clinic_id=:'clinic';
select private.professional_record_external(v.id,'00000000-0000-0000-0000-000000000154',clock_timestamp(),repeat('c',64),'Synthetic evidence only',clock_timestamp()+interval '1 day') from private.professional_profile_versions v join public.professional_profiles p on p.id=v.profile_id where p.clinic_id=:'clinic';
set role authenticated;
select pg_temp.expect_error($q$select public.rx_vial_open(current_setting('test.clinic')::uuid,current_setting('test.product')::uuid,'Synthetic lot','10','2020-01-01T00:00:00Z',null,null,repeat('a',48))$q$,'explicit_permission_required');
select public.permission_procedure_set(:'clinic',null,'Synthetic medication care',true) as procedure \gset
select public.permission_procedure_set(:'clinic',null,'Synthetic unrelated type',true) as other \gset
select set_config('test.procedure',:'procedure',false);
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','clinical.authorize',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','clinical.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','patient.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','vial.manage',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','vial.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.schedule',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','clinical.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','patient.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','medication.report',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','vial.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','procedure.perform',:'procedure',now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','drug.administer',:'other',now()+interval '1 day','Synthetic wrong type');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select public.clinical_scope_bind(:'case_id','cuidados',:'procedure',true,'Synthetic permission test','Synthetic binding') as binding \gset
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000152','cuidados',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('b',48));
select public.rx_vial_open(:'clinic',:'product','SYNTHETIC-LOT','10',to_char(clock_timestamp()-interval '3 minutes','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),null,null,repeat('c',48)) as vial \gset
select public.rx_vial_open(:'clinic',:'controlled','SYNTHETIC-CONTROL','10',to_char(clock_timestamp()-interval '3 minutes','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),null,null,repeat('d',48)) as controlled_vial \gset
select set_config('test.vial',:'vial',false);
select pg_temp.expect_error(format('select public.rx_vial_adjust(%L,''ajuste'',''1'',''Synthetic'',repeat(''x'',48))',:'controlled_vial'),'controlled_or_unverified_vial_adjustment_denied');
select pg_temp.expect_error($q$select public.rx_vial_adjust(current_setting('test.vial')::uuid,'ajuste','1','Synthetic',repeat('8',48))$q$,'controlled_or_unverified_vial_adjustment_denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
select set_config('test.data',jsonb_build_object('product_version_id',:'product','quantity','2','unit','ml','route','synthetic route','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id',:'vial','lot','')::text,false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.data')::jsonb,repeat('e',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','drug.administer',:'procedure',now()+interval '1 day','Synthetic administer') as administer \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
select set_config('test.data',(current_setting('test.data')::jsonb||jsonb_build_object('observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))::text,false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.data')::jsonb,repeat('e',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','vial.draw',:'procedure',now()+interval '1 day','Synthetic draw') as draw \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
-- Capturing a past time does not make a newly granted permission retroactive.
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.data')::jsonb,repeat('e',48))$q$,'permission_not_valid_at_application');
select set_config('test.data',(current_setting('test.data')::jsonb||jsonb_build_object('observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))::text,false);
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||jsonb_build_object('performed_by','00000000-0000-0000-0000-000000000151'),repeat('f',48))$q$,'own_act_only');
select public.rx_medication_report(:'case_id',current_setting('test.data')::jsonb,repeat('e',48)) as record \gset
select public.rx_medication_report(:'case_id',current_setting('test.data')::jsonb,repeat('e',48)) as retry \gset
select pg_temp.assert_true(:'record'=:'retry','report retry duplicated');
select set_config('test.record',:'record',false);
select pg_temp.assert_true((public.rx_operational_permissions(:'clinic',:'case_id')->'scopes'->0->>'administer')::boolean,'scope capability missing');
reset role;
select content_hash as record_hash from public.medication_records where id=:'record' \gset
select set_config('test.hash',:'record_hash',false);
select pg_temp.assert_true(private.rx_vial_balance(:'vial')=8,'draw did not subtract exactly once');
select pg_temp.assert_true((select administer_grant_id=:'administer' and draw_grant_id=:'draw' and scope_binding_id=:'binding' and procedure_type_id=:'procedure' from public.medication_records where id=:'record'),'application authority missing');
select pg_temp.assert_true(not exists(select 1 from public.controlled_drug_reviews where record_id=:'record'),'report auto-validated');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_review(current_setting('test.record')::uuid,current_setting('test.hash'),'validada','Synthetic',repeat('1',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','medication.validate',null,now()+interval '1 day','Synthetic validation') as validate_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_review(current_setting('test.record')::uuid,repeat('0',64),'validada','Synthetic',repeat('1',48))$q$,'exact_current_record_required');
select public.rx_medication_review(:'record',:'record_hash','validada','Synthetic review',repeat('1',48)) as review \gset
select public.rx_medication_review(:'record',:'record_hash','validada','Synthetic review',repeat('1',48));
select public.rx_medication_report(:'case_id',current_setting('test.data')::jsonb||jsonb_build_object('quantity','1','replaces_id',:'record','correction_reason','Synthetic correction'),repeat('2',48)) as correction \gset
select public.rx_medication_report(:'case_id',current_setting('test.data')::jsonb||jsonb_build_object('quantity','1','replaces_id',:'record','correction_reason','Synthetic correction'),repeat('2',48));
select pg_temp.expect_error($q$select public.rx_medication_review(current_setting('test.record')::uuid,current_setting('test.hash'),'validada','New attempt on old content',repeat('3',48))$q$,'exact_current_record_required');
reset role;
select pg_temp.assert_true(private.rx_vial_balance(:'vial')=9,'correction duplicated or wrong accounting delta');
select pg_temp.assert_true((select quantity=2 from public.medication_records where id=:'record'),'original overwritten');
select pg_temp.assert_true((select correction_grant_id=:'validate_grant' and performed_by='00000000-0000-0000-0000-000000000152' and reported_by='00000000-0000-0000-0000-000000000151' from public.medication_records where id=:'correction'),'correction falsely claimed another application');
select pg_temp.assert_true((select count(*)=2 from public.medication_vial_movements where vial_id=:'vial'),'duplicate accounting movements');
select pg_temp.assert_true((select permission_grant_id=:'validate_grant' from public.controlled_drug_reviews where id=:'review'),'review authority missing');
-- Schedule uses a synthetic issued fixture, never a real unverified prescription.
insert into public.hospital_stays(clinic_id,patient_id,admitted_by) values(:'clinic',:'patient',auth.uid()) returning id as stay \gset
insert into public.prescriptions(clinic_id,case_id,patient_id,responsible_id,created_by,state) values(:'clinic',:'case_id',:'patient','00000000-0000-0000-0000-000000000151',auth.uid(),'issued') returning id as rx \gset
insert into public.prescription_items(clinic_id,prescription_id,product_version_id,quantity,unit,route,interval_text,duration_text) values(:'clinic',:'rx',:'product',1,'ml','synthetic route','synthetic interval','synthetic duration') returning id as item \gset
select set_config('test.rx',:'rx',false);select set_config('test.item',:'item',false);select set_config('test.stay',:'stay',false);
select set_config('test.times',jsonb_build_array(to_char(clock_timestamp()+interval '1 hour','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_schedule(null,null,null,'[]',repeat('4',48))$q$,'typed_medication_schedule_required');
select pg_temp.expect_error($q$select public.rx_schedule_typed(current_setting('test.rx')::uuid,current_setting('test.item')::uuid,current_setting('test.stay')::uuid,'cuidados',current_setting('test.times')::jsonb,null,repeat('4',48))$q$,'explicit_alert_delay_required');
select public.rx_schedule_typed(:'rx',:'item',:'stay','cuidados',current_setting('test.times')::jsonb,15,repeat('4',48)) as tasks \gset
select public.rx_schedule_typed(:'rx',:'item',:'stay','cuidados',current_setting('test.times')::jsonb,15,repeat('4',48)) as task_retry \gset
select pg_temp.assert_true(:'tasks'::jsonb=:'task_retry'::jsonb,'schedule receipt changed');
reset role;
select id as task from public.hospital_tasks where clinic_id=:'clinic' \gset
select set_config('test.task',:'task',false);
update public.hospital_tasks set due_at=clock_timestamp()-interval '1 minute' where id=:'task';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
select set_config('test.task_data',(current_setting('test.data')::jsonb||jsonb_build_object('quantity','1','hospital_task_id',:'task','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))::text,false);
set role authenticated;
select public.rx_medication_report(:'case_id',current_setting('test.task_data')::jsonb,repeat('5',48));
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.task_data')::jsonb,repeat('6',48))$q$,'task_already_confirmed');
reset role;
select pg_temp.assert_true(private.rx_vial_balance(:'vial')=8,'hospital confirmation duplicated draw');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_vial_close(current_setting('test.vial')::uuid,'7','',repeat('7',48))$q$,'discrepancy_mvZ_note_required');
select public.rx_vial_close(:'vial','7','Synthetic discrepancy note',repeat('7',48));
reset role;
select pg_temp.assert_true((select expected=8 and measured=7 and difference=-1 from public.medication_vial_reconciliations where vial_id=:'vial'),'reconciliation erased discrepancy');
-- Grant revocation prevents a receipt from bypassing fresh authorization.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_revoke(:'draw','Synthetic draw revoked');
select pg_temp.expect_error($q$select public.rx_vials(current_setting('test.clinic')::uuid)$q$,'explicit_permission_required');
select pg_temp.assert_true(not exists(select 1 from public.medication_vials where clinic_id=current_setting('test.clinic')::uuid),'admin read leaked vials');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medication_report(current_setting('test.case')::uuid,current_setting('test.data')::jsonb,repeat('e',48))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);
select public.create_clinic('Synthetic medication other clinic');
set role authenticated;
select pg_temp.expect_error($q$select public.rx_medications(current_setting('test.case')::uuid)$q$,'case_access_required');
select pg_temp.expect_error($q$select public.rx_operational_permissions(current_setting('test.clinic')::uuid,null)$q$,'clinic_membership_required');
reset role;
set role anon;
select pg_temp.expect_error('select public.rx_operational_permissions(null,null)','permission denied');
select pg_temp.expect_error('select public.rx_medication_report(null,null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
