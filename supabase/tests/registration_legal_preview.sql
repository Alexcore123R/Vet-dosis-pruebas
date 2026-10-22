-- PostgreSQL fixture only. No real legal text, no acceptance records.
create function pg_temp.assert_true(ok boolean, message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',message;end if;end$$;

select pg_temp.assert_true(
 has_function_privilege('anon','public.beta_registration_legal()','EXECUTE'),
 'anonymous visitors cannot read published legal preview'
);
select pg_temp.assert_true(
 not has_table_privilege('anon','private.beta_privacy_notices','SELECT'),
 'private privacy table exposed'
);
set role anon;
select pg_temp.assert_true(
 (public.beta_registration_legal()->'terms'->>'version')='terms-with-privacy'
 and (public.beta_registration_legal()->'privacy'->>'version')='notice-1'
 and (public.beta_registration_legal()->'privacy'->>'content')='Synthetic privacy',
 'published pair not available for signup'
);
reset role;

begin;
insert into private.beta_terms(version,content,content_hash,published,published_at)
values('newer-without-privacy','Synthetic unbound version',
       encode(sha256(convert_to('Synthetic unbound version','UTF8')),'hex'),
       true,clock_timestamp()+interval '1 day');
-- Fail closed: never fall back to an older privacy-bound version.
set role anon;
select pg_temp.assert_true(
 public.beta_registration_legal() is null,
 'preview fell back to old documents after latest version changed'
);
reset role;
rollback;
