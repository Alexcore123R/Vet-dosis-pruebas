-- Synthetic setup only; never apply remotely.
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000001','platform@example.test',now()),
 ('00000000-0000-0000-0000-000000000002','legacy@example.test',now()),
 ('00000000-0000-0000-0000-000000000003','new@example.test',now()),
 ('00000000-0000-0000-0000-000000000004','other@example.test',now());
insert into private.platform_admins(user_id) values('00000000-0000-0000-0000-000000000001');
insert into private.beta_terms(version,content,content_hash,published,published_at) values('test-0','Synthetic historical terms',encode(sha256(convert_to('Synthetic historical terms','UTF8')),'hex'),true,now()-interval '5 days');
insert into private.beta_enrollments(user_id,email,starts_at,expires_at,terms_version,terms_hash,accepted_at)
select '00000000-0000-0000-0000-000000000002','legacy@example.test',now()-interval '5 days',now()+interval '55 days',version,content_hash,now()-interval '5 days' from private.beta_terms where version='test-0';
create table public.terms_test_mutations(id integer primary key);
grant insert,select on public.terms_test_mutations to authenticated;
