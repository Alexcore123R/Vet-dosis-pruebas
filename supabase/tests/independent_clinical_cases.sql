-- Synthetic context, not a clinical consultation or clinical recommendation.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select set_config('test.clinic',:'clinic',false);
select set_config('test.context',jsonb_build_object('patient_id',:'patient','responsible_id','00000000-0000-0000-0000-000000000151','kind','clinical_history','clinical_date',current_date,'reason','Synthetic independent context')::text,false);
select count(*) as documents_before from public.form_documents \gset
select count(*) as observations_before from public.clinical_observations \gset
select count(*) as acts_before from public.clinical_procedure_acts \gset
select count(*) as grants_before from public.person_procedure_authorizations \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic')->'actions'->>'create')::boolean,'reader/job acquired registration');
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb,repeat('2111',12))$q$,'explicit_permission_required');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','clinical.case.prepare',null,clock_timestamp()+interval '1 day','Synthetic intake preparation') as prepare_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true((public.clinical_workspace(:'clinic')->'actions'->>'create')::boolean,'explicit preparer denied');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.clinical_workspace(:'clinic')->'responsibles') r where r->>'id'='00000000-0000-0000-0000-000000000151'),'eligible responsible missing');
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb-'responsible_id',repeat('2111',12))$q$,'explicit_verified_case_responsible_required');
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb||'{"temperature":"1"}',repeat('2111',12))$q$,'case_context_fields_only');
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb||'{"clinical_date":"2026-02-30"}',repeat('2111',12))$q$,'invalid_clinical_date');
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb-'clinical_date',repeat('2111',12))$q$,'explicit_clinical_date_required');
select public.clinical_case_register(:'clinic',current_setting('test.context')::jsonb,repeat('2111',12)) as new_case \gset
select set_config('test.new_case',:'new_case',false);
select pg_temp.assert_true(public.clinical_case_register(:'clinic',current_setting('test.context')::jsonb,repeat('2111',12))=:'new_case','retry created duplicate case');
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb||'{"reason":"Different context"}',repeat('2111',12))$q$,'operation_payload_changed');
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'new_case')->'documents'='[]'::jsonb,'invented original PDF');
select pg_temp.assert_true(not(public.clinical_workspace(:'clinic',:'new_case')->'actions'->>'observe')::boolean,'case registration granted observations');
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'new_case')->'act_scopes'='[]'::jsonb,'case registration granted procedures');
select pg_temp.expect_error($q$select * from private.clinical_case_intakes$q$,'permission denied');reset role;
select pg_temp.assert_true((select document_id is null and asa is null and ekg is null and antecedents is null from public.clinical_cases where id=:'new_case'),'clinical fields/PDF invented');
select pg_temp.assert_true((select actor_id='00000000-0000-0000-0000-000000000170' and prepare_grant_id=:'prepare_grant' and responsible_profile_version_id is not null from private.clinical_case_intakes where case_id=:'new_case'),'registration trace missing');
select pg_temp.assert_true((select count(*)=:documents_before from public.form_documents),'created a PDF/document');
select pg_temp.assert_true((select count(*)=:observations_before from public.clinical_observations),'created observations');
select pg_temp.assert_true((select count(*)=:acts_before from public.clinical_procedure_acts),'created attention');
select pg_temp.assert_true((select count(*)=:grants_before from public.person_procedure_authorizations),'authorized procedure');
select pg_temp.assert_true(not exists(select 1 from public.case_staff_assignments where case_id=:'new_case'),'invented actual case team');
-- The selected responsible can explicitly configure/authorize later, not on intake.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true((public.clinical_workspace(:'clinic',:'new_case')->'actions'->>'bind')::boolean,'responsible cannot configure new case');reset role;
-- Current authority is checked before receipt replay.
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'prepare_grant','Synthetic intake revoke');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb,repeat('2111',12))$q$,'explicit_permission_required');rollback;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb,repeat('2112',12))$q$,'clinical_access_denied');reset role;
set role anon;select pg_temp.expect_error($q$select public.clinical_case_register(current_setting('test.clinic')::uuid,current_setting('test.context')::jsonb,repeat('2112',12))$q$,'permission denied');reset role;
-- New context -> explicit authority -> signed clinical sheet, without an original PDF.
select id as evaluation_type from private.procedure_types where clinic_id=:'clinic' and name='Synthetic focused evaluation' \gset
select id as template from public.form_template_versions where reason='Synthetic separately attributed clinical template' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.clinical_scope_bind(:'new_case','evaluacion',:'evaluation_type',true,'Synthetic case follow-up','Synthetic explicit mapping');
select public.clinical_authorize(:'new_case','00000000-0000-0000-0000-000000000152','evaluacion',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('2131',12));reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_draft_create(:'clinic',:'patient',:'template','00000000-0000-0000-0000-000000000151',jsonb_build_object('clinical_date',current_date,'reason','Synthetic independent follow-up','privacy_url','https://example.test/privacy'),'{}',repeat('2132',12))->>'id' as followup \gset
select public.form_attention_select(:'followup',1,'00000000-0000-0000-0000-000000000152',:'new_case',repeat('2133',12));
select public.form_document_authorship_sign(:'followup',2,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('2134',12)) as author \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);set role authenticated;
select public.form_attention_sign(:'followup',2,'Synthetic presenter','[[0.2,0.3],[0.4,0.6],[0.8,0.7],null]',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true,repeat('2135',12)) as attention \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_review_submit(:'followup',2,:'author',:'attention',repeat('2136',12));reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_authorize_individual(:'followup',2,true,repeat('2137',12));
select public.form_document_snapshot(:'followup')->>'content_hash' as content_hash \gset
reset role;set role service_role;
select public.form_register_pdf(:'followup',2,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-INDEPENDENT-FOLLOWUP','UTF8'),'base64'),null,encode(decode('89504e470d0a1a0a','hex'),'base64'))->>'hash' as pdf_hash \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_finalize(:'followup',2,:'pdf_hash');
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'new_case')->'documents'->0->>'id'=:'followup','signed follow-up missing from independent case');
select pg_temp.assert_true(public.clinical_workspace(:'clinic',:'new_case')->'documents'->0->'is_original'='false'::jsonb,'nullable original broke signed document projection');
select pg_temp.assert_true(public.form_read_pdf(:'followup')->>'hash'=:'pdf_hash','signed follow-up original bytes unreadable');
reset role;
select pg_temp.assert_true((select document_id is null from public.clinical_cases where id=:'new_case'),'follow-up silently replaced case original');
select pg_temp.assert_true((select count(*)=:observations_before from public.clinical_observations),'follow-up invented measurements');
select pg_temp.assert_true((select count(*)=:acts_before from public.clinical_procedure_acts),'follow-up auto-published a procedure act');
