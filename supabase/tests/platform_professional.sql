create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
-- The platform user has no clinical enrollment; real guard is enabled in this fixture.
select set_config('request.jwt.claim.sub','',false);
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000005','professional@example.test',now());
insert into public.clinics(name,created_by) values('Synthetic platform review clinic','00000000-0000-0000-0000-000000000005') returning id as clinic \gset
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000005','admin');
insert into public.professional_profiles(clinic_id,user_id) values(:'clinic','00000000-0000-0000-0000-000000000005') returning id as profile \gset
insert into private.professional_profile_versions(profile_id,version,name,license,created_by) values(:'profile',1,'Synthetic Professional','TEST-ONLY','00000000-0000-0000-0000-000000000005') returning id as version \gset
select private.professional_record_external(:'version','00000000-0000-0000-0000-000000000001',now(),repeat('c',64),'Synthetic private evidence',now()+interval '1 day') as verification \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
set role authenticated;
select pg_temp.expect_error('select public.platform_beta_professional_list()','platform_admin_mfa_required');
select pg_temp.expect_error('select public.platform_beta_professional_revoke('''||:'verification'||''',''Synthetic'')','platform_admin_mfa_required');
reset role;
select set_config('request.jwt.claims','{"aal":"aal2"}',false);
select set_config('request.path','/rpc/platform_beta_professional_list',false);
set role authenticated;
select private.beta_request_guard();
select pg_temp.assert_true(jsonb_array_length(public.platform_beta_professional_list())=1,'global evidence not visible with MFA');
select pg_temp.expect_error('select private.professional_record_external(null,null,null,null,null,null)','permission denied');
reset role;
select pg_temp.assert_true(private.professional_current(:'clinic','00000000-0000-0000-0000-000000000005'),'verification not current before revocation');
select set_config('request.path','/rpc/platform_beta_professional_revoke',false);
set role authenticated;
select private.beta_request_guard();
select public.platform_beta_professional_revoke(:'verification','Synthetic revocation with gate enabled');
select public.platform_beta_professional_revoke(:'verification','Synthetic retry');
select pg_temp.assert_true((public.platform_beta_professional_list()->0->>'revoked')::boolean,'revocation not shown');
reset role;
select pg_temp.assert_true(not private.professional_current(:'clinic','00000000-0000-0000-0000-000000000005'),'global revocation ignored');
select pg_temp.assert_true(not exists(select 1 from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000001'),'platform user enrolled clinically');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
set role authenticated;
select pg_temp.expect_error('select public.platform_beta_professional_list()','platform_admin_mfa_required');
select pg_temp.expect_error('select public.platform_beta_professional_revoke('''||:'verification'||''',''Synthetic'')','platform_admin_mfa_required');
reset role;
set role anon;
select pg_temp.expect_error('select public.platform_beta_professional_list()','permission denied');
reset role;
