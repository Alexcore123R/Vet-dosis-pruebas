-- Synthetic access and write checks for the clinic-operations cutover.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000181','synthetic-operations-staff@example.test',now());
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000181','mvz');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
-- Flutter rejects the entire response if a module is missing, even when false.
select pg_temp.assert_true(
 (select array_agg(key order by key) from jsonb_each(public.app_module_workspace(:'clinic')->'modules')) =
 array['agenda','backup','clinical','forms','hospital','inventory','patients','prescriptions','sales','statistics'],
 'module contract differs from Flutter ModuleAccess.read');
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'modules'->>'statistics')::boolean,'statistics opened without sales read');
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'modules'->>'backup')::boolean,'backup opened without permission');
select pg_temp.assert_true(not (public.app_module_workspace(:'clinic')->'modules'->>'agenda')::boolean,'operations opened without a grant');
select pg_temp.assert_true(not (public.ops_dashboard(:'clinic')->'sections'->>'services')::boolean,'services opened without a grant');
select pg_temp.expect_error(format('select public.ops_write(%L,%L,%L::jsonb,%L)',:'clinic','service','{"name":"Grooming","category":"estetica","price":"200","commission_kind":"bono","commission_value":"0"}',repeat('a',48)),'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000181','service.manage',null,clock_timestamp()+interval '1 day','Synthetic clinic operations access');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select pg_temp.assert_true((public.app_module_workspace(:'clinic')->'modules'->>'agenda')::boolean,'service grant did not expose operations module');
select pg_temp.assert_true((public.ops_dashboard(:'clinic')->'sections'->>'services')::boolean,'service grant did not expose services section');
select public.ops_write(:'clinic','service','{"name":"Grooming","category":"estetica","price":"200","commission_kind":"bono","commission_value":"0"}'::jsonb,repeat('b',48)) as service_id \gset
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_dashboard(:'clinic')->'services') s where s->>'id' = :'service_id'),'service write was not returned by dashboard');
select pg_temp.assert_true(not (public.ops_dashboard(:'clinic')->'sections'->>'suppliers')::boolean,'service grant leaked suppliers');
select public.ops_write(:'clinic','service','{"name":"Ecografía abdominal","category":"imagen","subcategory":"Abdominal personalizada","price":"450","commission_kind":"bono","commission_value":"0"}'::jsonb,repeat('f',48)) as imaging_id \gset
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_dashboard(:'clinic')->'services') s where s->>'id'=:'imaging_id' and s->>'subcategory'='Abdominal personalizada' and s->>'category'='imagen'),'custom subcategory not saved');
select public.ops_write(:'clinic','service',jsonb_build_object('id',:'imaging_id','version',1,'name','Ecografía abdominal','category','imagen','subcategory','Control','price','450','commission_kind','bono','commission_value','0'),repeat('1',48));
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_dashboard(:'clinic')->'services') s where s->>'id'=:'imaging_id' and s->>'subcategory'='Control'),'custom subcategory not edited');

select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_dashboard(:'clinic')->'services') s where s->>'id'=:'service_id' and s->>'category'='estetica'),'category not persisted');
select public.ops_write(:'clinic','service',jsonb_build_object('id',:'service_id','version',1,'name','Synthetic surgery','category','cirugia','price','300','commission_kind','bono','commission_value','0'),repeat('d',48));
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_dashboard(:'clinic')->'services') s where s->>'id'=:'service_id' and s->>'category'='cirugia' and s->>'version'='2'),'category edit not persisted');
select pg_temp.expect_error(format('select public.ops_write(%L,%L,%L::jsonb,%L)',:'clinic','service','{"name":"Invalid","category":"invalid","price":"100","commission_kind":"bono","commission_value":"0"}',repeat('e',48)),'check constraint');

reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000181','supplier.manage',null,clock_timestamp()+interval '1 day','Synthetic supplier access');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select pg_temp.assert_true((public.ops_dashboard(:'clinic')->'sections'->>'suppliers')::boolean,'supplier grant did not expose suppliers');
select public.ops_write(:'clinic','supplier','{"name":"Synthetic supplier","phone":"+5215550100100","notes":"fixture"}'::jsonb,repeat('c',48));
select pg_temp.assert_true(jsonb_array_length(public.ops_dashboard(:'clinic')->'suppliers')=1,'supplier write was not returned by dashboard');
reset role;
set role anon;
select pg_temp.expect_error(format('select public.ops_dashboard(%L)',:'clinic'),'permission denied');reset role;
