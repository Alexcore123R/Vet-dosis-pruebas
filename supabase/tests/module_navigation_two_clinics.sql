-- Synthetic, isolated two-account/two-clinic module permissions.
-- Appended after the 13N module navigation fixture; never run in Supabase.
-- Each .sql is executed in a separate psql session by run_module_navigation_dashboard.sh.
-- Recreate session-local assertions; pg_temp helpers from the preceding test do not persist.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $audit$
begin
  if v is distinct from true then raise exception 'ASSERT: %',msg;end if;
end
$audit$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $audit$
begin
  begin
    execute sql;
  exception when others then
    if position(expected in sqlerrm)>0 then return;end if;
    raise;
  end;
  raise exception 'Expected rejection: %',expected;
end
$audit$;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-0000-0000-000000000181','synthetic-owner-a@example.test',now()),
('00000000-0000-0000-0000-000000000182','synthetic-owner-b@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);
select public.create_clinic('Synthetic P0 Module Clinic A') as clinic_a \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',false);
select public.create_clinic('Synthetic P0 Module Clinic B') as clinic_b \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);
set role authenticated;
select pg_temp.assert_true(
  (select bool_and(not value::boolean) from jsonb_each(public.app_module_workspace(:'clinic_a')->'modules')),
  'Clinic A visual admin unexpectedly granted module access');
select pg_temp.expect_error(format('select public.app_module_workspace(%L)',:'clinic_b'),'current_member_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',false);
set role authenticated;
select pg_temp.assert_true(
  (select bool_and(not value::boolean) from jsonb_each(public.app_module_workspace(:'clinic_b')->'modules')),
  'Clinic B visual admin unexpectedly granted module access');
select pg_temp.expect_error(format('select public.app_module_workspace(%L)',:'clinic_a'),'current_member_required');
reset role;
select set_config('request.jwt.claim.sub','',false);
set role anon;
select pg_temp.expect_error(format('select public.app_module_workspace(%L)',:'clinic_a'),'permission denied');
reset role;
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),
  'Synthetic test changed beta admission flags');
select pg_temp.assert_true(not(select enforcement_enabled or migration_reviewed from private.permission_policy),
  'Synthetic test activated permissions globally');
select 'Two distinct synthetic clinic accounts remained isolated without inferred grants' as result;
