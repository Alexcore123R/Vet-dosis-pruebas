-- Synthetic content/identity only. No clinical procedure or consent accepted.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as patient from public.vet_patients where id=(select patient_id from public.clinical_cases where title='Synthetic medication case') \gset
select id as template_version from public.form_template_versions where reason='Synthetic reviewed template' \gset
select set_config('test.clinic',:'clinic',false);select set_config('test.patient',:'patient',false);select set_config('test.template',:'template_version',false);
select count(*) as cases_before from public.clinical_cases \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.prepare',null,clock_timestamp()+interval '1 day','Synthetic document preparer') as prep_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','form.authorize',null,clock_timestamp()+interval '1 day','Synthetic future reviewer') as reviewer_grant \gset
select pg_temp.expect_error($q$select public.form_documents_list(current_setting('test.clinic')::uuid)$q$,'document_read_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true((public.form_document_workspace(:'clinic')->>'can_prepare')::boolean,'visual stylist cannot prepare with grant');
select pg_temp.expect_error($q$select public.form_document_draft_create(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,current_setting('test.template')::uuid,null,'{}','{}',repeat('1810',12))$q$,'explicit_verified_responsible_required');
select pg_temp.expect_error($q$select public.form_document_draft_create(current_setting('test.clinic')::uuid,current_setting('test.patient')::uuid,current_setting('test.template')::uuid,auth.uid(),'{}','{}',repeat('1810',12))$q$,'explicit_verified_responsible_required');
select public.form_document_draft_create(:'clinic',:'patient',:'template_version','00000000-0000-0000-0000-000000000151','{"mvz_name":"Forged input ignored","mvz_license":"Forged input ignored"}','{}',repeat('1811',12))->>'id' as draft \gset
select set_config('test.draft',:'draft',false);
select pg_temp.assert_true(public.form_documents_list(:'clinic')->0->'values'->>'mvz_name'<>'Forged input ignored','caller changed verified responsible data');
select pg_temp.expect_error($q$select public.form_document_authorship_sign(current_setting('test.draft')::uuid,1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',false,repeat('1812',12))$q$,'document_authorship_confirmation_required');
select pg_temp.expect_error($q$select public.form_document_authorship_sign(current_setting('test.draft')::uuid,1,'','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1812',12))$q$,'document_author_name_required');
select pg_temp.expect_error($q$select public.form_document_authorship_sign(current_setting('test.draft')::uuid,1,'Synthetic participant','[[0.1,0.1],[0.1,0.1]]',true,repeat('1812',12))$q$,'signature_required');
select public.form_document_authorship_sign(:'draft',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1812',12)) as attestation \gset
select public.form_document_authorship_sign(:'draft',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1812',12));
select pg_temp.expect_error($q$select snapshot from public.form_documents$q$,'permission denied');
select pg_temp.expect_error($q$select * from public.form_signatures$q$,'permission denied');
select pg_temp.expect_error($q$select * from private.form_authorship_attestations$q$,'permission denied');
select pg_temp.expect_error($q$select public.form_document_prepare(current_setting('test.draft')::uuid,1,'[]','[]')$q$,'attributed_form_authorization_required');
select pg_temp.expect_error($q$select public.form_document_use_profile(current_setting('test.draft')::uuid,1,null,true)$q$,'shared_form_signature_closed');
select pg_temp.expect_error($q$select public.form_document_finalize(current_setting('test.draft')::uuid,1,'x')$q$,'attributed_form_authorization_required');
reset role;
select pg_temp.assert_true((select count(*)=1 from private.form_authorship_attestations where document_id=:'draft'),'signature duplicated');
select pg_temp.assert_true((select signer_id='00000000-0000-0000-0000-000000000170' and member_since is not null and permission_grant_id=:'prep_grant' from private.form_authorship_attestations where id=:'attestation'),'signer identity/authority missing');
select pg_temp.assert_true((private.form_authorship_for_draft((select d from public.form_documents d where id=:'draft'),:'attestation'))->>'scope'='document_authorship','signature became clinical act');
select pg_temp.assert_true((select state='draft' and prepared_at is null and accepted_at is null and pdf_hash is null from public.form_documents where id=:'draft'),'own signature authorized or issued document');
select pg_temp.assert_true((select count(*)=:cases_before from public.clinical_cases),'draft published clinical case');
select pg_temp.assert_true((select count(*)=0 from public.form_signatures where document_id=:'draft'),'tutor or MVZ signature invented');
select pg_temp.expect_error($q$update private.form_authorship_attestations set signer_name='Altered' where document_id=current_setting('test.draft')::uuid$q$,'append_only_permission_record');
-- A saved content/membrete change increments revision and invalidates the signature.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_save(:'draft',1,'{}','{"header":"Synthetic changed header"}');
select pg_temp.expect_error($q$select public.form_document_authorship_sign(current_setting('test.draft')::uuid,1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1812',12))$q$,'document_revision_conflict');
reset role;
select pg_temp.expect_error(format('select private.form_authorship_for_draft((select d from public.form_documents d where id=%L),%L)',:'draft',:'attestation'),'document_authorship_stale');
select pg_temp.assert_true((select count(*)=1 from private.form_authorship_attestations where document_id=:'draft'),'prior evidence deleted');
-- The selected MVZ may read, but cannot attest as the document's author.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.form_documents_list(:'clinic')) x where x->>'id'=:'draft'),'selected responsible cannot read draft');
select pg_temp.expect_error($q$select public.form_document_authorship_sign(current_setting('test.draft')::uuid,2,'MVZ signer','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1813',12))$q$,'draft_author_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_documents_list(current_setting('test.clinic')::uuid)$q$,'document_read_required');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.form_document_workspace(current_setting('test.clinic')::uuid)$q$,'permission denied');
reset role;
set role service_role;
select pg_temp.expect_error($q$select public.form_register_pdf(current_setting('test.draft')::uuid,2,'x','x','x','x')$q$,'attributed_form_authorization_required');
reset role;

begin;
select pv.version,pv.name,pv.license from public.professional_profiles p join lateral(select * from private.professional_profile_versions where profile_id=p.id order by version desc limit 1) pv on true where p.clinic_id=:'clinic' and p.user_id='00000000-0000-0000-0000-000000000151' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_profile_save(:'clinic',:version,:'name',:'license','','{"keep":true}',repeat('1819',12));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_document_save(current_setting('test.draft')::uuid,2,'{}','{}')$q$,'draft_responsible_profile_changed');
rollback;
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'reviewer_grant','Synthetic selection revoked');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.form_document_save(current_setting('test.draft')::uuid,2,'{}','{}')$q$,'draft_responsible_authority_changed');
rollback;

-- A historical signed artifact remains readable with current explicit read
-- authority; it is not reissued, rewritten or turned into a new attestation.
reset role;
insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,state,revision,values,branding,snapshot,content_hash,pdf_hash,accepted_at,created_by)
 select clinic_id,patient_id,version_id,responsible_id,'signed',1,values,branding,snapshot-'document_flow_version'-'draft_authority',repeat('a',64),encode(sha256(convert_to('%PDF-SYNTHETIC-ARCHIVE','UTF8')),'hex'),clock_timestamp(),created_by from public.form_documents where id=:'draft' returning id as archive,pdf_hash as archive_hash \gset
select set_config('test.archive',:'archive',false);
insert into private.form_artifacts(document_id,revision,content_hash,pdf,pdf_hash,renderer_version)
 values(:'archive',1,repeat('a',64),convert_to('%PDF-SYNTHETIC-ARCHIVE','UTF8'),:'archive_hash','SYNTHETIC BOUNDARY FIXTURE ONLY');
select pg_temp.expect_error($q$update public.form_documents set revision=2 where id=current_setting('test.archive')::uuid$q$,'signed_document_is_immutable');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(public.form_read_pdf(:'archive')->>'hash'=:'archive_hash','historical artifact lost');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.form_documents_list(:'clinic')) x where x->'snapshot' ? 'mvz_signature' or x->'snapshot' ? 'tutor_signature' or x->'snapshot' ? 'draft_authority'),'document list exposed signature/context');
reset role;
-- The focused clinical draft can be saved without SOAP/vitals or a published act.
select id as clinical_base,schema as clinical_schema from public.form_template_versions where clinic_id is null and schema->>'type'='clinical_history' order by version desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_template_save(:'clinic',null,null,:'clinical_base',:'clinical_schema',true,'Synthetic focused clinical template',repeat('1831',12))->>'id' as clinical_template \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_draft_create(:'clinic',:'patient',:'clinical_template','00000000-0000-0000-0000-000000000151','{}','{"header":"Synthetic focused clinical draft"}',repeat('1832',12))->>'id' as clinical_draft \gset
reset role;
select pg_temp.assert_true((select state='draft' and not(values ? 'weight') and not(values ? 'temperature') and not(values ? 'subjective') from public.form_documents where id=:'clinical_draft'),'blank clinical fields were required or filled as normal');
select pg_temp.assert_true((select count(*)=:cases_before from public.clinical_cases),'clinical draft published an act');
