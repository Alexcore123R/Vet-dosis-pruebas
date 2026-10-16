-- Explicitly fictitious fixtures; no clinical references are imported.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-prescription-workflow' \gset
select set_config('test.clinic',:'clinic',false),set_config('test.case',:'case_id',false);
select set_config('test.items',jsonb_build_array(jsonb_build_object('product_version_id',:'product','quantity','1','unit','ml','route','Synthetic route','interval','Synthetic interval','duration','Synthetic duration','care','Synthetic care'))::text,false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','prescription.authorize',null,clock_timestamp()+interval '1 day','Synthetic standing test');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_standing_offer(current_setting('test.case')::uuid,'00000000-0000-0000-0000-000000000170',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),false,repeat('a1',24))$q$,'responsible_explicit_authorization_required');
select pg_temp.expect_error($q$select public.rx_standing_offer(current_setting('test.case')::uuid,'00000000-0000-0000-0000-000000000170',to_char((clock_timestamp()+interval '2 days') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true,repeat('a1',24))$q$,'standing_expiry_outside_permissions');
select public.rx_standing_offer(:'case_id','00000000-0000-0000-0000-000000000170',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true,repeat('a1',24)) as delegation \gset
select set_config('test.delegation',:'delegation',false);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_create(:'case_id',current_setting('test.items')::jsonb,'','Synthetic standing',repeat('a2',24))->>'id' as rx \gset
select set_config('test.rx',:'rx',false);
select public.rx_consultation_sign(:'rx',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('a3',24)) as signed \gset
select set_config('test.signed',:'signed',false);
select pg_temp.expect_error($q$select public.rx_prepare_standing(current_setting('test.rx')::uuid,1,current_setting('test.signed')::uuid,'Synthetic participant',current_setting('test.delegation')::uuid)$q$,'standing_authorization_unavailable');
select pg_temp.expect_error($q$select public.rx_standing_accept(current_setting('test.delegation')::uuid,false,repeat('a4',24))$q$,'standing_acceptance_required');
select public.rx_standing_accept(:'delegation',true,repeat('a4',24));
select public.rx_standing_accept(:'delegation',true,repeat('a4',24));
select public.rx_standing_accept(:'delegation',true,repeat('a5',24));
select pg_temp.assert_true(public.rx_prescription_permissions(:'clinic')->>'mode'='individual_standing','contract missing');
select pg_temp.assert_true(not(public.rx_prescription_permissions(:'clinic')->>'can_authorize')::boolean,'recipient became authorizer');
select public.rx_prepare_standing(:'rx',1,:'signed','Synthetic participant',:'delegation');
select public.rx_pdf_snapshot('prescription',:'rx')->>'content_hash' as content_hash \gset
select pg_temp.assert_true((public.rx_pdf_snapshot('prescription',:'rx')->'snapshot'->'prescription_identity'->'authorization'->>'mode')='standing','wrong actual act label');
reset role;
select pg_temp.assert_true((select count(*)=1 from public.audit_log where action='ordinary_standing_authorization_accepted' and entity_id=:'delegation'),'acceptance duplicated');
set role service_role;
select public.rx_pdf_register('prescription',:'rx',2,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-STANDING','UTF8'),'base64'),'iVBORw0KGgo=')->>'hash' as pdf_hash \gset
reset role;
select set_config('test.pdf',:'pdf_hash',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,2,current_setting('test.pdf'))$q$,'standing_recipient_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_finalize(:'rx',2,:'pdf_hash');
select public.rx_finalize(:'rx',2,:'pdf_hash');
select pg_temp.assert_true(jsonb_array_length(public.rx_standing_workspace(:'clinic')->'events')=0,'recipient sees responsible inbox');
reset role;
select pg_temp.assert_true((select state='issued' and issued_by=prepared_by and authorized_by=responsible_id and issued_by<>authorized_by from public.prescriptions where id=:'rx'),'false attribution');
select pg_temp.assert_true((select count(*)=1 from private.rx_standing_events where prescription_id=:'rx'),'duplicate or missing inbox event');
select id as event from private.rx_standing_events where prescription_id=:'rx' \gset
select set_config('test.event',:'event',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_standing_review(current_setting('test.event')::uuid,'','',true,'')$q$,'responsible_review_only');
-- A new responsible profile version never silently reuses the old offer.
reset role;
begin;
insert into private.professional_profile_versions(profile_id,version,name,license,registration,signature,created_by)
select v.profile_id,v.version+1,v.name,v.license,v.registration,v.signature,v.created_by from private.professional_profile_versions v
where v.id=(select profile_version_id from public.professional_delegations where id=:'delegation');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,2,current_setting('test.pdf'))$q$,'standing_authorization_unavailable');
rollback;
-- Invalidating a grant or membership epoch cannot revive a prior authorization.
reset role;
begin;
insert into private.permission_revocations(grant_id,revoked_by,reason)
select authority_grant_id,'00000000-0000-0000-0000-000000000150','Synthetic revocation' from public.professional_delegations where id=:'delegation';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,2,current_setting('test.pdf'))$q$,'standing_authorization_unavailable');
rollback;
begin;
update public.clinic_members set created_at=created_at+interval '1 second' where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000170';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,2,current_setting('test.pdf'))$q$,'case_access_required');
rollback;
select id as controlled from public.prescriptions where instructions='Synthetic controlled instructions' \gset
select set_config('test.controlled',:'controlled',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_prepare_standing(current_setting('test.controlled')::uuid,3,current_setting('test.signed')::uuid,'Synthetic participant',current_setting('test.delegation')::uuid)$q$,'controlled_responsible_only');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_standing_accept(current_setting('test.delegation')::uuid,true,repeat('aa',24))$q$,'standing_recipient_only');
select pg_temp.expect_error($q$select public.rx_standing_workspace(current_setting('test.clinic')::uuid)$q$,'case_access_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
-- A second prepared document is invalidated by resuming review, not silently issued.
select public.rx_create(:'case_id',current_setting('test.items')::jsonb,'','Synthetic resume',repeat('a6',24))->>'id' as pending \gset
select public.rx_consultation_sign(:'pending',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('a7',24)) as signed_pending \gset
select public.rx_prepare_standing(:'pending',1,:'signed_pending','Synthetic participant',:'delegation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true((public.rx_standing_workspace(:'clinic')->'events'->0->>'reviewed')='false','viewing marked reviewed');
select pg_temp.assert_true(public.rx_standing_resume(:'clinic','Synthetic returned',repeat('a8',24))=1,'resume count');
select pg_temp.assert_true(public.rx_standing_resume(:'clinic','Synthetic returned',repeat('a8',24))=1,'resume idempotence');
select public.rx_return_to_draft(:'pending',2,'Synthetic individual review required');
select pg_temp.assert_true(public.rx_snapshot(:'pending')->>'state'='draft','owner cannot return standing to draft');
select public.rx_standing_review(:'event',:'content_hash',:'pdf_hash',true,'Synthetic post review');
select public.rx_standing_review(:'event',:'content_hash',:'pdf_hash',true,'Synthetic post review');
select pg_temp.assert_true((public.rx_standing_workspace(:'clinic')->'events'->0->>'reviewed')='true','post review missing');
reset role;
select pg_temp.assert_true((select count(*)=1 from private.rx_standing_reviews where event_id=:'event'),'duplicate review');
select pg_temp.assert_true((select content_hash=:'content_hash' and pdf_hash=:'pdf_hash' and state='issued' from public.prescriptions where id=:'rx'),'post review changed original');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.rx_finalize(current_setting('test.rx')::uuid,2,current_setting('test.pdf'))$q$,'standing_authorization_unavailable');
select pg_temp.expect_error($q$select * from private.rx_standing_events$q$,'permission denied');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.rx_standing_workspace(current_setting('test.clinic')::uuid)$q$,'permission denied');
reset role;
