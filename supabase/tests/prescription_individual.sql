-- Fictitious permissions/products only. Does not publish any real dose or source.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id,patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
insert into public.vet_owners(clinic_id,name,created_by) values(:'clinic','Synthetic owner','00000000-0000-0000-0000-000000000150') returning id as owner \gset
update public.vet_patients set owner_id=:'owner' where id=:'patient';
insert into public.medication_product_versions(product_key,version,name,presentation,unit,classification,quantified_prescription,source,source_status)
 values('synthetic-prescription-workflow',1,'Synthetic ordinary','Synthetic only','ml','no_controlado',false,'{"reference":"SYNTHETIC TEST ONLY; NOT CLINICAL"}','verificada') returning id as product \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','prescription.prepare',null,clock_timestamp()+interval '1 day','Synthetic new workflow') as prep_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','prescription.authorize',null,clock_timestamp()+interval '1 day','Synthetic') as authorize_grant \gset
reset role;
-- A visual job label does not defeat explicitly granted preparation rights.
update public.clinic_members set role='estilista' where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000170';
select set_config('test.clinic',:'clinic',false);
select set_config('test.items',jsonb_build_array(jsonb_build_object('product_version_id',:'product','quantity','1','unit','ml','route','Synthetic route','interval','Synthetic interval','duration','Synthetic duration','care','Synthetic care'))::text,false);
select set_config('test.case',:'case_id',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_create(:'case_id',current_setting('test.items')::jsonb,'','Synthetic instructions',repeat('e1',24))->>'id' as rx \gset
select pg_temp.assert_true(public.rx_profiles(:'clinic') is not null,'job label blocked profile metadata');
select pg_temp.assert_true(public.rx_delegations(:'clinic')='[]'::jsonb,'job label blocked legacy history');
select set_config('test.rx',:'rx',false);
select pg_temp.assert_true((public.rx_prescription_permissions(:'clinic')->>'can_prepare')::boolean,'preparer cannot create');
select pg_temp.assert_true(not (public.rx_prescription_permissions(:'clinic')->>'can_authorize')::boolean,'preparer became authorizer');
select pg_temp.expect_error($q$select public.rx_prepare(current_setting('test.rx')::uuid,1,null,true,null)$q$,'attributed_prescription_preparation_required');
select pg_temp.expect_error($q$select public.rx_prepare_attributed(current_setting('test.rx')::uuid,1,'00000000-0000-0000-0000-000000000999','Synthetic preparer')$q$,'consultation_signature_required');
select public.rx_consultation_sign(:'rx',1,'Synthetic person who attended','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('e2',24)) as signed \gset
select pg_temp.assert_true((public.rx_consultations(:'rx')->0->>'id')=:'signed','signed consultation missing');
select public.rx_prepare_attributed(:'rx',1,:'signed','Different value must not replace own signer name');
select pg_temp.assert_true((public.rx_snapshot(:'rx')->>'state')='awaiting_authorization','preparation emitted without authorization');
select pg_temp.expect_error($q$select public.rx_pdf_snapshot('prescription',current_setting('test.rx')::uuid)$q$,'individual_authorization_required');
select pg_temp.expect_error($q$select public.rx_authorize_individual(current_setting('test.rx')::uuid,2,true)$q$,'individual_responsible_only');
select pg_temp.expect_error($q$select snapshot from public.prescriptions where id=current_setting('test.rx')::uuid$q$,'permission denied');
select pg_temp.assert_true(not(public.rx_snapshot(:'rx') ? 'snapshot'),'detail leaks signature vectors');
reset role;
select pg_temp.assert_true((select prepared_by='00000000-0000-0000-0000-000000000170' and authorized_by is null and prepare_grant_id=:'prep_grant' and snapshot->'prescription_identity'->'consultation'->>'name'='Synthetic person who attended' from public.prescriptions where id=:'rx'),'preparer attribution changed');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_authorize_individual(current_setting('test.rx')::uuid,2,false)$q$,'individual_authorization_confirmation_required');
select public.rx_authorize_individual(:'rx',2,true);
select public.rx_pdf_snapshot('prescription',:'rx')->>'content_hash' as content_hash \gset
select pg_temp.assert_true((public.rx_pdf_snapshot('prescription',:'rx')->'snapshot'->'prescription_identity'->'responsible'->>'user_id')=auth.uid()::text,'responsible identity lost');
select pg_temp.expect_error($q$select public.rx_pdf_register('prescription',current_setting('test.rx')::uuid,3,'wrong','','')$q$,'permission denied');
reset role;
set role service_role;
select public.rx_pdf_register('prescription',:'rx',3,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-PRESCRIPTION','UTF8'),'base64'),'iVBORw0KGgo=')->>'hash' as pdf_hash \gset
reset role;
select set_config('test.pdf',:'pdf_hash',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,3,current_setting('test.pdf'))$q$,'individual_responsible_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,3,'wrong hash')$q$,'reviewed_prescription_mismatch');
select public.rx_finalize(:'rx',3,:'pdf_hash');
select public.rx_finalize(:'rx',3,:'pdf_hash');
reset role;
select pg_temp.assert_true((select issued_by='00000000-0000-0000-0000-000000000151' and authorized_by=issued_by and prepared_by='00000000-0000-0000-0000-000000000170' and authorization_grant_id=:'authorize_grant' and state='issued' from public.prescriptions where id=:'rx'),'individual authority trace lost');
select pg_temp.assert_true((select count(*)=1 from public.audit_log where entity_id=:'rx' and action='prescription_issued'),'double confirmation duplicated issuance');
select pg_temp.expect_error($q$update public.prescriptions set instructions='Rewrite issued history' where id=current_setting('test.rx')::uuid$q$,'issued_prescription_is_immutable');
-- Returning an unissued document for correction invalidates the prior signature.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_create(:'case_id',current_setting('test.items')::jsonb,'','Synthetic correction',repeat('e3',24))->>'id' as corrected_rx \gset
select set_config('test.corrected',:'corrected_rx',false);
select public.rx_consultation_sign(:'corrected_rx',1,'Synthetic person who attended','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('e4',24)) as previous_signature \gset
select set_config('test.previous_signature',:'previous_signature',false);
select public.rx_prepare_attributed(:'corrected_rx',1,:'previous_signature','Synthetic person who attended');
select pg_temp.expect_error($q$select public.rx_return_to_draft(current_setting('test.corrected')::uuid,2,'')$q$,'prescription_correction_reason_required');
select public.rx_return_to_draft(:'corrected_rx',2,'Synthetic correction requested');
select pg_temp.assert_true((public.rx_snapshot(:'corrected_rx')->>'state')='draft','correction did not return draft');
select pg_temp.expect_error($q$select public.rx_prepare_attributed(current_setting('test.corrected')::uuid,3,current_setting('test.previous_signature')::uuid,'Synthetic person who attended')$q$,'consultation_signature_stale');
select public.rx_consultation_sign(:'corrected_rx',3,'Synthetic person who attended','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('e5',24)) as new_signature \gset
select public.rx_prepare_attributed(:'corrected_rx',3,:'new_signature','Synthetic person who attended');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_authorize_individual(:'corrected_rx',4,true);
select public.rx_pdf_snapshot('prescription',:'corrected_rx')->>'content_hash' as corrected_hash \gset
reset role;
select pg_temp.assert_true(not exists(select 1 from private.rx_artifacts where entity_id=:'corrected_rx'),'unreviewed correction has artifact');
-- Verified statuses below are isolated test fixtures, never clinical references.
insert into public.medication_product_versions(product_key,version,name,presentation,unit,classification,quantified_prescription,source,source_status)
 values('synthetic-controlled-workflow',1,'Synthetic controlled','Synthetic only','ml','grupo_i',true,'{"reference":"SYNTHETIC TEST ONLY; NOT CLINICAL"}','verificada') returning id as controlled_product \gset
insert into public.rx_regulatory_versions(kind,version,source,source_status,required_fields)
 values('controlled_prescription',1,'{"reference":"SYNTHETIC TEST FORMAT; NOT A LEGAL REFERENCE"}','verificada',array['folio','patient','owner','signature']) returning id as control_format \gset
select v.name as responsible_name from private.professional_profile_versions v join public.professional_profiles p on p.id=v.profile_id where p.clinic_id=:'clinic' and p.user_id='00000000-0000-0000-0000-000000000151' order by v.version desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_create(:'case_id',jsonb_build_array(jsonb_build_object('product_version_id',:'controlled_product','quantity','1','unit','ml','route','Synthetic','interval','Synthetic','duration','Synthetic')),'SYNTHETIC-FOLIO-NOT-OFFICIAL','Synthetic controlled instructions',repeat('e6',24))->>'id' as controlled_rx \gset
select set_config('test.controlled_rx',:'controlled_rx',false);
select public.rx_consultation_sign(:'controlled_rx',1,:'responsible_name','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('e7',24)) as controlled_signature \gset
select public.rx_prepare_attributed(:'controlled_rx',1,:'controlled_signature',:'responsible_name');
select public.rx_authorize_individual(:'controlled_rx',2,true);
select public.rx_pdf_snapshot('prescription',:'controlled_rx')->>'content_hash' as control_hash \gset
reset role;
set role service_role;
select public.rx_pdf_register('prescription',:'controlled_rx',3,:'control_hash',encode(convert_to('%PDF-SYNTHETIC-CONTROLLED','UTF8'),'base64'),'iVBORw0KGgo=');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_snapshot(current_setting('test.controlled_rx')::uuid)$q$,'prescription_access_denied');
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.controlled_rx')::uuid,3,'wrong')$q$,'individual_responsible_only');
reset role;
-- A different verified version of the synthetic format requires new review.
insert into public.rx_regulatory_versions(kind,version,source,source_status,required_fields)
 values('controlled_prescription',2,'{"reference":"SYNTHETIC CHANGED TEST FORMAT; NOT A LEGAL REFERENCE"}','verificada',array['folio','patient','owner','signature']);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.controlled_rx')::uuid,3,'wrong')$q$,'prescription_regulation_changed');
reset role;
-- Expiry/revocation after rendering cannot use the successful old receipt.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'authorize_grant','Synthetic authorization revoked');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,3,current_setting('test.pdf'))$q$,'explicit_permission_required');
reset role;
set role service_role;
select pg_temp.expect_error($q$select public.rx_pdf_register('prescription',current_setting('test.rx')::uuid,3,'wrong','','')$q$,'prescription_authorization_changed');
select pg_temp.expect_error($q$select public.rx_pdf_register('prescription',current_setting('test.corrected')::uuid,5,'wrong','','')$q$,'prescription_authorization_changed');
reset role;
select pg_temp.assert_true(not exists(select 1 from private.rx_artifacts where entity_id=:'corrected_rx'),'revoked authority stored a new PDF');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_snapshot(current_setting('test.rx')::uuid)$q$,'prescription_access_denied');
select pg_temp.expect_error($q$select public.rx_delegate(null,null,null,'{}',null,null)$q$,'typed_standing_authorization_not_available');
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.rx_authorize_individual(uuid,integer,boolean)','execute'),'anonymous authorization');
select pg_temp.assert_true(not has_function_privilege('authenticated','private.rx_pdf_register_before_attribution(text,uuid,integer,text,text,text)','execute'),'old artifact registration bypass');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_profile_save(:'clinic',0,'Synthetic participant','','',null,repeat('e8',24));
reset role;
select pg_temp.assert_true(not private.clinical_professional_at(:'clinic','00000000-0000-0000-0000-000000000170',clock_timestamp()),'own declaration granted professional status');
-- Retiring an owned legacy grant remains possible without professional status.
insert into public.professional_delegations(clinic_id,profile_id,recipient_id,case_id,use_data,use_signature,prepare_ordinary,issue_ordinary,dispense_ordinary,valid_until,created_by)
select :'clinic',p.id,'00000000-0000-0000-0000-000000000151',null,true,false,false,false,false,clock_timestamp()+interval '1 day','00000000-0000-0000-0000-000000000170'
from public.professional_profiles p where p.clinic_id=:'clinic' and p.user_id='00000000-0000-0000-0000-000000000170' returning id as legacy_delegation \gset
set role authenticated;
select public.rx_delegate_revoke(:'legacy_delegation','Synthetic owner revocation',repeat('e9',24));
select pg_temp.assert_true((public.rx_delegations(:'clinic')->0->>'revoked')::boolean,'job label prevented owned revocation');
reset role;
