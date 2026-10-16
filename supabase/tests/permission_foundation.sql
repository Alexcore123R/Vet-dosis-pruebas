-- Synthetic identities and evidence only; never apply remotely.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000030','platform30@example.test',now()),
 ('00000000-0000-0000-0000-000000000031','admin31@example.test',now()),
 ('00000000-0000-0000-0000-000000000032','mvz32@example.test',now()),
 ('00000000-0000-0000-0000-000000000033','member33@example.test',now()),
 ('00000000-0000-0000-0000-000000000034','other34@example.test',now());
insert into private.platform_admins(user_id) values('00000000-0000-0000-0000-000000000030');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000031',false);
select public.create_clinic('Permissions synthetic A') as clinic \gset
select set_config('test.clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values
 (:'clinic','00000000-0000-0000-0000-000000000032','mvz'),
 (:'clinic','00000000-0000-0000-0000-000000000033','auxiliar');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000034',false);
select public.create_clinic('Permissions synthetic B') as other \gset
select set_config('test.other',:'other',false);
select pg_temp.assert_true((select count(*)=0 from private.member_permission_grants),'legacy roles became permissions');
select pg_temp.assert_true(not private.professional_current(:'clinic','00000000-0000-0000-0000-000000000032'),'legacy MVZ became verified');
select pg_temp.assert_true(not (select enforcement_enabled from private.permission_policy),'cutover enabled');
set role anon;
select pg_temp.expect_error('select public.permission_snapshot(current_setting(''test.clinic'')::uuid)','permission denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000031',false);
set role authenticated;
select pg_temp.expect_error('select * from private.professional_verifications','permission denied');
select pg_temp.expect_error('select private.professional_record_external(null,null,null,null,null,null)','permission denied');
select pg_temp.expect_error('select public.permission_grant(current_setting(''test.clinic'')::uuid,''00000000-0000-0000-0000-000000000031'',''prescription.authorize'',null,now()+interval ''1 day'',''Synthetic'')','verified_professional_required');
select public.permission_set_job(:'clinic','00000000-0000-0000-0000-000000000033','MVZ');
select public.permission_procedure_set(:'clinic',null,'Synthetic procedure A',true) as procedure \gset
select set_config('test.procedure',:'procedure',false);
select public.permission_procedure_set(:'clinic',null,'Synthetic procedure B',true) as procedure_b \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000033','drug.administer',:'procedure',now()+interval '1 day','Synthetic scope') as grant_id \gset
select pg_temp.expect_error('select public.permission_grant(current_setting(''test.clinic'')::uuid,''00000000-0000-0000-0000-000000000033'',''drug.administer'',current_setting(''test.procedure'')::uuid,now()+interval ''1 day'',''Duplicate synthetic'')','active_grant_already_exists');
select pg_temp.expect_error('select public.permission_grant(current_setting(''test.clinic'')::uuid,''00000000-0000-0000-0000-000000000033'',''drug.administer'',null,now()+interval ''1 day'',''Synthetic'')','procedure_scope_required');
select pg_temp.expect_error('select public.permission_grant(current_setting(''test.clinic'')::uuid,''00000000-0000-0000-0000-000000000034'',''patient.read'',null,now()+interval ''1 day'',''Synthetic'')','member_not_found');
select pg_temp.expect_error('select public.permission_grant(current_setting(''test.clinic'')::uuid,''00000000-0000-0000-0000-000000000033'',''patient.read'',null,now(),''Synthetic'')','future_expiry_required');
reset role;
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','drug.administer',:'procedure')=:'grant_id','scoped grant missing');
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','drug.administer',:'procedure_b') is null,'cross-procedure grant');
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','vial.draw',:'procedure') is null,'cross-action grant');
select pg_temp.assert_true(not private.professional_current(:'clinic','00000000-0000-0000-0000-000000000033'),'job label promoted');
-- Profile versions are self-entered unverified data until explicit evidence review.
insert into public.professional_profiles(clinic_id,user_id) values(:'clinic','00000000-0000-0000-0000-000000000032') returning id as profile \gset
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'profile',1,'Synthetic Professional','TEST-ONLY','00000000-0000-0000-0000-000000000032') returning id as version \gset
select set_config('test.version',:'version',false);
set role authenticated;
select pg_temp.expect_error('select public.permission_professional_review(current_setting(''test.clinic'')::uuid,current_setting(''test.version'')::uuid,now(),repeat(''a'',64),''Synthetic evidence'',now()+interval ''1 day'')','verified_responsible_required');
reset role;
select pg_temp.expect_error('select private.professional_record_external(current_setting(''test.version'')::uuid,''00000000-0000-0000-0000-000000000031'',now(),repeat(''a'',64),''Synthetic evidence'',now()+interval ''1 day'')','separate_platform_reviewer_required');
select private.professional_record_external(:'version','00000000-0000-0000-0000-000000000030',now(),repeat('a',64),'Synthetic evidence only',now()+interval '1 day') as verification \gset
select pg_temp.assert_true(private.professional_current(:'clinic','00000000-0000-0000-0000-000000000032'),'external review not effective');
set role authenticated;
select public.permission_responsible_propose(:'clinic','00000000-0000-0000-0000-000000000032',now()+interval '1 day') as designation \gset
select set_config('test.designation',:'designation',false);
select pg_temp.expect_error('select public.permission_responsible_respond(current_setting(''test.designation'')::uuid,true)','responsible_confirmation_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000032',false);
select pg_temp.assert_true(not private.permission_responsible(:'clinic'),'designation accepted by proposer');
set role authenticated;
select public.permission_responsible_respond(:'designation',true);
select pg_temp.expect_error('select public.permission_professional_review(current_setting(''test.clinic'')::uuid,current_setting(''test.version'')::uuid,now(),repeat(''b'',64),''Self evidence'',now()+interval ''1 day'')','self_review_forbidden');
reset role;
select pg_temp.assert_true(private.permission_responsible(:'clinic'),'accepted responsible missing');
-- A responsible can verify another member locally, never globally or in a second clinic.
insert into public.clinic_members(clinic_id,user_id,role) values(:'other','00000000-0000-0000-0000-000000000033','auxiliar');
insert into public.professional_profiles(clinic_id,user_id) values(:'clinic','00000000-0000-0000-0000-000000000033') returning id as local_profile \gset
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'local_profile',1,'Synthetic Local Professional','LOCAL-TEST','00000000-0000-0000-0000-000000000033') returning id as local_version \gset
insert into public.professional_profiles(clinic_id,user_id) values(:'other','00000000-0000-0000-0000-000000000033') returning id as other_profile \gset
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'other_profile',1,'Synthetic Local Professional','LOCAL-TEST','00000000-0000-0000-0000-000000000033');
set role authenticated;
select public.permission_professional_review(:'clinic',:'local_version',now(),repeat('b',64),'Synthetic local evidence',now()+interval '1 day') as local_verification \gset
reset role;
select pg_temp.assert_true(private.professional_current(:'clinic','00000000-0000-0000-0000-000000000033'),'local review missing');
select pg_temp.assert_true(not private.professional_current(:'other','00000000-0000-0000-0000-000000000033'),'local review became global');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000033',false);
set role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.permission_professional_snapshot(:'clinic')->'verifications')=1,'member evidence scope leaked');
select pg_temp.assert_true(jsonb_array_length(public.permission_snapshot(:'clinic')->'members')=1,'member team scope leaked');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000031',false);
set role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.permission_professional_snapshot(:'clinic')->'verifications')=0,'administrative role exposed evidence');
select public.permission_procedure_set(:'clinic',:'procedure','Synthetic procedure A',false);
reset role;
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','drug.administer',:'procedure') is null,'inactive procedure authorized');
set role authenticated;
select public.permission_procedure_set(:'clinic',:'procedure','Synthetic procedure A',true);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000032',false);
set role authenticated;
select public.permission_professional_revoke(:'local_verification','Synthetic local withdrawal');
reset role;
select pg_temp.assert_true(not private.professional_current(:'clinic','00000000-0000-0000-0000-000000000033'),'local revocation ineffective');
-- Cross-clinic and ordinary member cannot manage grants or read another clinic.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000034',false);
set role authenticated;
select pg_temp.expect_error('select public.permission_snapshot(current_setting(''test.clinic'')::uuid)','membership_required');
select pg_temp.expect_error('select public.permission_revoke(''' || :'grant_id' || ''',''Synthetic'')','admin_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000031',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000032','prescription.authorize',null,now()+interval '1 day','Synthetic reserved') as reserved \gset
select public.permission_revoke(:'grant_id','Synthetic revocation');
select public.permission_revoke(:'grant_id','Synthetic retry');
reset role;
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','drug.administer',:'procedure') is null,'revocation ineffective');
select pg_temp.assert_true((select count(*)=1 from private.permission_revocations where grant_id=:'grant_id'),'duplicate revocation');
-- Identity changes invalidate evidence; returning to the reviewed identity restores it.
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'profile',2,'Synthetic Professional','CHANGED','00000000-0000-0000-0000-000000000032');
select pg_temp.assert_true(not private.professional_current(:'clinic','00000000-0000-0000-0000-000000000032'),'stale license accepted');
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000032','prescription.authorize') is null,'reserved grant survived identity change');
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'profile',3,'Synthetic Professional','TEST-ONLY','00000000-0000-0000-0000-000000000032');
-- Platform revocation requires real MFA and separate identity.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000030',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
set role authenticated;
select pg_temp.expect_error('select public.permission_professional_revoke(''' || :'verification' || ''',''Synthetic'')','platform_admin_mfa_required');
reset role;
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
set role authenticated;
select public.permission_professional_revoke(:'verification','Synthetic review withdrawn');
reset role;
select pg_temp.assert_true(not private.professional_current(:'clinic','00000000-0000-0000-0000-000000000032'),'professional revocation ineffective');
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000032','prescription.authorize') is null,'reserved grant survived revocation');
-- Exact expiry uses statement time and does not grant a grace period.
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,granted_at,valid_until,reason)
select clinic_id,user_id,created_at,'patient.read','00000000-0000-0000-0000-000000000031',now()-interval '1 day',now(),'Synthetic expired' from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000033';
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','patient.read') is null,'expired grant effective');
-- Leave/rejoin never revives historical operational permission.
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select clinic_id,user_id,created_at,'patient.write','00000000-0000-0000-0000-000000000031',now()+interval '1 day','Synthetic membership epoch' from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000033';
delete from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000033';
insert into public.clinic_members(clinic_id,user_id,role,created_at) values(:'clinic','00000000-0000-0000-0000-000000000033','auxiliar',clock_timestamp()+interval '1 second');
select pg_temp.assert_true(private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000033','patient.write') is null,'rejoined member regained permissions');
select pg_temp.expect_error('delete from private.member_permission_grants','append_only_permission_record');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
