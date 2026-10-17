-- Synthetic capability projection only; no clinical values.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000180','synthetic-module-admin@example.test',now());
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000180','admin');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true((select bool_and(not value::boolean) from jsonb_each(public.app_module_workspace(:'clinic')->'modules')),'visual admin received module access');
select pg_temp.assert_true((select bool_and(not value::boolean) from jsonb_each(public.app_module_workspace(:'clinic')->'summaries')),'visual admin received dashboard summary');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','patient.read',null,clock_timestamp()+interval '1 day','Synthetic module projection') as grant_id \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true((public.app_module_workspace(:'clinic')->'modules'->>'patients')::boolean,'patient grant did not open patients');
select pg_temp.assert_true((public.app_module_workspace(:'clinic')->'summaries'->>'patients')::boolean,'patient read did not enable its summary');
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'modules'->>'clinical')::boolean,'patient grant leaked clinical module');
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'modules'->>'inventory')::boolean,'patient grant leaked inventory module');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic module revocation');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'modules'->>'patients')::boolean,'revoked module remained visible');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','inventory.manage',null,clock_timestamp()+interval '1 day','Synthetic manage without read');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true((public.app_module_workspace(:'clinic')->'modules'->>'inventory')::boolean,'management did not open module');
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'summaries'->>'inventory')::boolean,'management invented inventory read');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error(format('select public.app_module_workspace(%L)',:'clinic'),'current_member_required');reset role;
set role anon;
select pg_temp.expect_error(format('select public.app_module_workspace(%L)',:'clinic'),'permission denied');reset role;
