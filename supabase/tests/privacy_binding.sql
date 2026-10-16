-- Synthetic data only; local isolated PostgreSQL.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select pg_temp.assert_true(not exists(select 1 from public.terms_acceptances where privacy_version is not null),'fabricated historical privacy receipt');
insert into private.beta_privacy_notices(version,content,content_hash) values('notice-1','Synthetic privacy',encode(sha256(convert_to('Synthetic privacy','UTF8')),'hex'));
select pg_temp.expect_error($q$insert into private.beta_terms(version,content,content_hash,published,published_at,privacy_version) values('terms-invalid','T',encode(sha256(convert_to('T','UTF8')),'hex'),true,clock_timestamp(),'notice-1')$q$,'published_privacy_required');
update private.beta_privacy_notices set published=true,published_at=clock_timestamp() where version='notice-1';
insert into private.beta_terms(version,content,content_hash,published,published_at,privacy_version) values('terms-with-privacy','Synthetic bound terms',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'),true,clock_timestamp(),'notice-1');
update private.beta_policy set admissions_enabled=true,enforcement_enabled=true;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select set_config('request.headers','{"x-vetdosis-build":"1"}',false);
set role authenticated;
select pg_temp.assert_true(public.beta_status(1)->'terms'->'privacy'->>'content'='Synthetic privacy','notice not served with terms');
select pg_temp.expect_error($q$select public.beta_accept_terms('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'))$q$,'beta_privacy_changed');
select pg_temp.expect_error($q$select public.beta_accept_terms('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'),'notice-1','wrong')$q$,'beta_privacy_changed');
select public.beta_accept_terms('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'),'notice-1',encode(sha256(convert_to('Synthetic privacy','UTF8')),'hex'));
select public.beta_accept_terms('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'),'notice-1',encode(sha256(convert_to('Synthetic privacy','UTF8')),'hex'));
select pg_temp.assert_true((select count(*)=1 from public.terms_acceptances where terms_version='terms-with-privacy' and privacy_version='notice-1' and privacy_hash=encode(sha256(convert_to('Synthetic privacy','UTF8')),'hex')),'wrong receipt or duplicate');
reset role;
select pg_temp.assert_true((select terms_version='test-0' from private.beta_enrollments where user_id=auth.uid()),'admission replaced');
select pg_temp.expect_error($q$update public.terms_acceptances set privacy_hash='changed'$q$,'beta_version_is_immutable');
select pg_temp.expect_error($q$update private.beta_privacy_notices set content='changed' where version='notice-1'$q$,'beta_version_is_immutable');
-- An expired user records acknowledgement but cannot regain writes.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
set role authenticated;
select public.beta_accept_terms('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'),'notice-1',encode(sha256(convert_to('Synthetic privacy','UTF8')),'hex'));
select pg_temp.assert_true(public.beta_status(1)->>'mode'='read_export','expired trial renewed');
select pg_temp.expect_error('insert into public.terms_test_mutations values(90)','beta_read_export_only');
select pg_temp.assert_true((select count(*)=1 from public.terms_acceptances where terms_version='terms-with-privacy'),'another user receipt leaked');
reset role;
-- New admission cannot be partially committed without its notice acknowledgement.
select set_config('request.jwt.claim.sub','',false);
insert into private.beta_email_approvals(email,enabled,changed_by,reason) values('other@example.test',true,'00000000-0000-0000-0000-000000000001','Synthetic approval');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
set role authenticated;
select pg_temp.expect_error($q$select public.beta_enroll('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'))$q$,'beta_privacy_changed');
reset role;
select pg_temp.assert_true(not exists(select 1 from private.beta_enrollments where user_id=auth.uid()),'partial admission retained');
set role authenticated;
select public.beta_enroll('terms-with-privacy',encode(sha256(convert_to('Synthetic bound terms','UTF8')),'hex'),null,'notice-1',encode(sha256(convert_to('Synthetic privacy','UTF8')),'hex'));
select pg_temp.assert_true((select privacy_version='notice-1' from public.terms_acceptances),'new admission missing notice');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.beta_accept_terms('x','y','z','w')$q$,'permission denied');
select pg_temp.expect_error('select * from public.terms_acceptances','permission denied');
reset role;
