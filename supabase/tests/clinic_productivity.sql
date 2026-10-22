-- Synthetic scheduling, isolation, capacity and idempotency checks.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into public.subscription_grants(clinic_id,plan_code,source,starts_at,ends_at,reference) values(:'clinic','clinic','gift',now()-interval '1 hour',now()+interval '1 day','synthetic-productivity');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000150','team.manage',null,now()+interval '1 day','Synthetic productivity manager');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','team.read',null,now()+interval '1 day','Synthetic productivity reader');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000152','team.read',null,now()+interval '1 day','Synthetic productivity reader');
select public.ops_productivity_write(:'clinic','profile','{"availability":{"00000000-0000-0000-0000-000000000151":[0],"00000000-0000-0000-0000-000000000152":[1]},"daily_minutes":30,"spaces":"Synthetic clinic"}',(md5('productivity-a')||left(md5('productivity-a'),16)));
select public.ops_productivity_write(:'clinic','routine','{"title":"Barrer","area":"Recepción","weekdays":[0,1,2],"assignees":["00000000-0000-0000-0000-000000000151","00000000-0000-0000-0000-000000000152"],"estimated_minutes":20}',(md5('productivity-b')||left(md5('productivity-b'),16))) as routine \gset
select public.ops_productivity_write(:'clinic','generate','{"week":"2026-10-19"}',(md5('productivity-c')||left(md5('productivity-c'),16)));
select public.ops_productivity_write(:'clinic','generate','{"week":"2026-10-19"}',(md5('productivity-c')||left(md5('productivity-c'),16)));
select public.ops_productivity_write(:'clinic','generate','{"week":"2026-10-19"}',(md5('productivity-d')||left(md5('productivity-d'),16)));
select pg_temp.assert_true(jsonb_array_length(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks')=3,'regeneration duplicated tasks');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'scheduled_on'='2026-10-19' and t->>'assigned_to'='00000000-0000-0000-0000-000000000151'),'monday availability ignored');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'scheduled_on'='2026-10-20' and t->>'assigned_to'='00000000-0000-0000-0000-000000000152'),'tuesday availability ignored');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'scheduled_on'='2026-10-21' and t->>'assigned_to' is null),'no availability should leave unassigned');
select public.ops_productivity_write(:'clinic','routine','{"title":"Trapear","weekdays":[0],"assignees":["00000000-0000-0000-0000-000000000151"],"estimated_minutes":20}',(md5('productivity-e')||left(md5('productivity-e'),16)));
select public.ops_productivity_write(:'clinic','generate','{"week":"2026-10-19"}',(md5('productivity-f')||left(md5('productivity-f'),16)));
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'title'='Trapear' and t->>'assigned_to' is null),'daily capacity ignored');
select pg_temp.expect_error(format('select public.ops_productivity_write(%L,%L,%L::jsonb,%L)',:'clinic','generate','{"week":"2026-10-20"}',(md5('productivity-g')||left(md5('productivity-g'),16))),'monday_required');
select pg_temp.expect_error(format('select public.ops_productivity_write(%L,%L,%L::jsonb,%L)',:'clinic','routine','{"title":"Invalid","weekdays":[0],"assignees":["00000000-0000-0000-0000-000000000154"],"estimated_minutes":15}',(md5('productivity-h')||left(md5('productivity-h'),16))),'assignee_wrong_clinic');
select t->>'id' as monday from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'title'='Barrer' and t->>'scheduled_on'='2026-10-19' \gset
select t->>'id' as tuesday from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'title'='Barrer' and t->>'scheduled_on'='2026-10-20' \gset
reset role;select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true(public.ops_productivity_read(:'clinic','2026-10-19')->'profile'='{}'::jsonb,'reader saw business profile');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.ops_productivity_read(:'clinic','2026-10-19')->'tasks') t where t->>'id'=:'tuesday'),'reader saw another member task');
select public.ops_productivity_write(:'clinic','complete',jsonb_build_object('id',:'monday'),(md5('productivity-i')||left(md5('productivity-i'),16)));
select pg_temp.expect_error(format('select public.ops_productivity_write(%L,%L,%L::jsonb,%L)',:'clinic','complete',jsonb_build_object('id',:'tuesday'),(md5('productivity-j')||left(md5('productivity-j'),16))),'task_unavailable');
select pg_temp.expect_error(format('select public.ops_productivity_write(%L,%L,%L::jsonb,%L)',:'clinic','generate','{"week":"2026-10-19"}',(md5('productivity-k')||left(md5('productivity-k'),16))),'team_access_required');
reset role;set role anon;
select pg_temp.expect_error(format('select public.ops_productivity_read(%L,%L)',:'clinic','2026-10-19'),'permission denied');
reset role;
