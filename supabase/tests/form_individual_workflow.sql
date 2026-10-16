-- Synthetic workflow only; no clinical recommendation or remote deployment.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as draft from public.form_documents where branding->>'header'='Synthetic changed header' and state='draft' \gset
select set_config('test.clinic',:'clinic',false);select set_config('test.draft',:'draft',false);
select count(*) as cases_before from public.clinical_cases \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','form.prepare',null,clock_timestamp()+interval '1 day','Synthetic independent presenter') as presenter_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(public.form_document_workspace(:'clinic')->>'mode'='individual_forms','new contract not announced');
select public.form_document_save(:'draft',2,'{"signer_name":"Synthetic tutor","signer_id":"SYNTHETIC-ID","privacy_url":"https://example.test/privacy","procedure":"Synthetic proposed procedure","information":"Synthetic information"}','{"header":"Synthetic individual flow"}');
select public.form_attention_select(:'draft',3,'00000000-0000-0000-0000-000000000152',null,repeat('1911',12));
select public.form_attention_select(:'draft',3,'00000000-0000-0000-0000-000000000152',null,repeat('1911',12));
select public.form_document_authorship_sign(:'draft',4,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1912',12)) as authorship \gset
select pg_temp.expect_error($q$select public.form_attention_sign(current_setting('test.draft')::uuid,4,'Wrong signer','[[0.2,0.3],[0.4,0.6],[0.8,0.7],null]','2026-10-16T00:00:00Z',true,repeat('1913',12))$q$,'actual_attention_signer_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);set role authenticated;
select pg_temp.assert_true((public.form_document_flow(:'draft')->'actions'->>'sign_attention')::boolean,'presenter cannot attest own explanation');
select to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as observed \gset
select public.form_attention_sign(:'draft',4,'Synthetic presenter','[[0.2,0.3],[0.4,0.6],[0.8,0.7],null]',:'observed',true,repeat('1913',12)) as attention \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_review_submit(:'draft',4,:'authorship',:'attention',repeat('1914',12));
select pg_temp.expect_error($q$select public.form_authorize_individual(current_setting('test.draft')::uuid,4,true,repeat('1915',12))$q$,'selected_responsible_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_authorize_individual(current_setting('test.draft')::uuid,4,false,repeat('1915',12))$q$,'individual_form_review_required');
select public.form_authorize_individual(:'draft',4,true,repeat('1915',12));
select public.form_document_preview_snapshot(:'draft')->>'content_hash' as preview_content \gset
select pg_temp.assert_true(public.form_document_preview_snapshot(:'draft')->'snapshot'->'form_identity'->'tutor'='null'::jsonb,'tutor signature invented');
select pg_temp.assert_true(not(public.form_document_preview_snapshot(:'draft')->'snapshot' ? 'mvz_signature'),'profile signature borrowed');
reset role;
set role service_role;
select public.form_preview_register(:'draft',4,:'preview_content',encode(convert_to('%PDF-SYNTHETIC-PREVIEW','UTF8'),'base64'))->>'hash' as preview_hash \gset
reset role;
select set_config('test.preview_hash',:'preview_hash',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_tutor_capture(current_setting('test.draft')::uuid,4,repeat('0',64),'[[0.15,0.25],[0.35,0.55],[0.75,0.65],null]',true,repeat('1916',12))$q$,'reviewed_tutor_preview_required');
select pg_temp.expect_error($q$select public.form_tutor_capture(current_setting('test.draft')::uuid,4,current_setting('test.preview_hash'),'[[0.15,0.25],[0.35,0.55],[0.75,0.65],null]',false,repeat('1916',12))$q$,'real_tutor_review_and_signature_required');
select public.form_tutor_capture(:'draft',4,:'preview_hash','[[0.15,0.25],[0.35,0.55],[0.75,0.65],null]',true,repeat('1916',12));
select public.form_document_snapshot(:'draft')->>'content_hash' as final_content \gset
select pg_temp.assert_true(public.form_document_snapshot(:'draft')->'snapshot'->'form_identity'->'attention'->>'user_id'='00000000-0000-0000-0000-000000000152','actual presenter changed');
reset role;
-- Recheck all authority after rendering, not only when snapshot was read.
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'presenter_grant','Synthetic render-time revocation');reset role;set role service_role;
select pg_temp.expect_error(format('select public.form_register_pdf(%L,4,%L,%L,%L,%L)',current_setting('test.draft'),:'final_content',encode(convert_to('%PDF-SYNTHETIC-FINAL','UTF8'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64')),'attention_authority_changed');
rollback;
set role service_role;
select public.form_register_pdf(:'draft',4,:'final_content',encode(convert_to('%PDF-SYNTHETIC-FINAL','UTF8'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'))->>'hash' as final_hash \gset
select pg_temp.assert_true(public.form_register_pdf(:'draft',4,:'final_content',encode(convert_to('%PDF-SYNTHETIC-SECOND','UTF8'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'))->>'hash'=:'final_hash','second renderer overwrote first artifact');
reset role;
select set_config('test.final_hash',:'final_hash',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_document_finalize(current_setting('test.draft')::uuid,4,current_setting('test.final_hash'))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.issue',null,clock_timestamp()+interval '1 day','Synthetic explicit issuer');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_document_finalize(current_setting('test.draft')::uuid,4,repeat('0',64))$q$,'reviewed_pdf_mismatch');
reset role;
select pg_temp.assert_true((select count(*)=0 from private.form_flow_events where document_id=:'draft' and kind='issuance'),'document issued before explicit confirmation');
select pg_temp.assert_true((select count(*)=:cases_before from public.clinical_cases),'consent invented clinical case');
select pg_temp.assert_true((select count(*)=0 from public.form_signatures where document_id=:'draft'),'borrowed profile signature created');
select pg_temp.expect_error($q$update private.form_flow_events set payload='{}' where document_id=current_setting('test.draft')::uuid$q$,'append_only_permission_record');
set role anon;select pg_temp.expect_error($q$select public.form_document_flow(current_setting('test.draft')::uuid)$q$,'permission denied');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_document_flow(current_setting('test.draft')::uuid)$q$,'document_access_denied');reset role;
-- Focused clinical sheet: explicit existing case and per-procedure authority.
select id as new_base,schema as new_schema from public.form_template_versions where clinic_id is null and schema->>'type'='clinical_history' order by version desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_template_save(:'clinic',null,null,:'new_base',:'new_schema',true,'Synthetic separately attributed clinical template',repeat('1920',12))->>'id' as new_clinical_version \gset
reset role;
select patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_draft_create(:'clinic',:'patient',:'new_clinical_version','00000000-0000-0000-0000-000000000151','{}','{"header":"Synthetic attributed clinical"}',repeat('192a',12))->>'id' as clinical_draft \gset
reset role;
select id as case_id,patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select set_config('test.clinical_draft',:'clinical_draft',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_procedure_set(:'clinic',null,'Synthetic focused evaluation',true) as procedure \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','procedure.perform',:'procedure',clock_timestamp()+interval '1 day','Synthetic focused evaluation') as procedure_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.clinical_scope_bind(:'case_id','evaluacion',:'procedure',true,'Synthetic focused evaluation','Synthetic binding') as binding \gset
select public.clinical_authorize(:'case_id','00000000-0000-0000-0000-000000000152','evaluacion',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('1921',12));reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_save(:'clinical_draft',1,jsonb_build_object('privacy_url','https://example.test/privacy','clinical_date',current_date,'reason','Synthetic focused evaluation'),'{}');
select pg_temp.expect_error($q$select public.form_attention_select(current_setting('test.clinical_draft')::uuid,2,'00000000-0000-0000-0000-000000000152',null,repeat('1922',12))$q$,'eligible_matching_case_required');
select public.form_attention_select(:'clinical_draft',2,'00000000-0000-0000-0000-000000000152',:'case_id',repeat('1922',12));
select public.form_document_authorship_sign(:'clinical_draft',3,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1923',12)) as cauthor \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);set role authenticated;
select to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as observed \gset
select public.form_attention_sign(:'clinical_draft',3,'Synthetic presenter','[[0.2,0.3],[0.4,0.6],[0.8,0.7],null]',:'observed',true,repeat('1924',12)) as cattention \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_review_submit(:'clinical_draft',3,:'cauthor',:'cattention',repeat('1925',12));reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_authorize_individual(:'clinical_draft',3,true,repeat('1926',12));
select pg_temp.assert_true(public.form_document_snapshot(:'clinical_draft')->'snapshot'->'form_identity'->'tutor'='null'::jsonb,'clinical sheet required tutor signature');
select pg_temp.assert_true(not(public.form_document_snapshot(:'clinical_draft')->'values' ? 'temperature'),'temperature filled as normal');
reset role;
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'procedure_grant','Synthetic procedure revocation');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_document_snapshot(current_setting('test.clinical_draft')::uuid)$q$,'attention_case_authority_changed');rollback;
-- Retain actual server snapshots only in this isolated synthetic fixture.
create table private.synthetic_form_render_snapshots(label text primary key,snapshot jsonb not null);
insert into private.synthetic_form_render_snapshots select 'clinical',snapshot from public.form_documents where id=:'clinical_draft';
-- Correction preserves evidence and invalidates both signatures and authorization.
select count(*) as clinical_events from private.form_flow_events where document_id=:'clinical_draft' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_review_reject(:'clinical_draft',3,'Synthetic correction required',repeat('1927',12));
select public.form_review_reject(:'clinical_draft',3,'Synthetic correction required',repeat('1927',12));reset role;
select pg_temp.assert_true((select count(*)=:clinical_events from private.form_flow_events where document_id=:'clinical_draft'),'correction erased prior proof');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_review_submit(current_setting('test.clinical_draft')::uuid,4,null,null,repeat('1928',12))$q$,'document_authorship_stale');
select public.form_document_reopen(:'clinical_draft',4,'00000000-0000-0000-0000-000000000151','Synthetic fresh review',repeat('1929',12));
select public.form_document_reopen(:'clinical_draft',4,'00000000-0000-0000-0000-000000000151','Synthetic fresh review',repeat('1929',12));reset role;
