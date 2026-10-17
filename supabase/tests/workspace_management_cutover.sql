-- Synthetic workspace-management cutover only. No real clinical content.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset

set role service_role;
select public.plan_grant_server(
 :'clinic','clinic','gift',
 clock_timestamp()-interval '1 hour',
 clock_timestamp()+interval '1 day',
 'synthetic:workspace-management:'||:'clinic'
);
reset role;

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000190','synthetic-workspace-manager@example.test',now()),
      ('00000000-0000-0000-0000-000000000191','synthetic-personal-manager@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000190','admin')
on conflict(clinic_id,user_id) do nothing;

-- Visual admin is not workspace-management authority.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000190',false);set role authenticated;
select pg_temp.assert_true(public.workspace_management_status(:'clinic')=false,'visual admin reported as workspace manager');
select pg_temp.expect_error(format('select public.clinic_team_snapshot(%L)',:'clinic'),'workspace_manage_required');
select pg_temp.expect_error(format($q$select public.att_settings_save(%L,'{"latitude":20.7,"longitude":-103.4,"radius_m":100,"max_accuracy_m":50,"privacy_notice":"Aviso sintético de ubicación para pruebas."}'::jsonb)$q$,:'clinic'),'workspace_manage_required');
select pg_temp.expect_error(format('select public.plan_payment_history(%L)',:'clinic'),'payment_history_denied');
reset role;

-- Service role cannot manufacture a clinic AI key for a visual admin without the capability.
set role service_role;
select pg_temp.expect_error(format($q$select public.ai_key_store_server('00000000-0000-0000-0000-000000000190','clinic',%L,'openai',repeat('c',24),repeat('n',16))$q$,:'clinic'),'workspace_manage_required');
reset role;

-- Existing permission administrator grants the explicit management capability.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000190','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic workspace management') as manage_grant \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000190',false);set role authenticated;
select pg_temp.assert_true(public.workspace_management_status(:'clinic'),'explicit workspace manager not projected');
select pg_temp.assert_true(jsonb_array_length(public.clinic_team_snapshot(:'clinic')->'members')>0,'manager cannot read team');
select public.att_settings_save(:'clinic','{"latitude":20.7,"longitude":-103.4,"radius_m":100,"max_accuracy_m":50,"privacy_notice":"Aviso sintético de ubicación para pruebas."}'::jsonb);
select pg_temp.assert_true(public.att_qr(:'clinic') ? 'token','manager cannot issue attendance QR');
select pg_temp.assert_true(public.plan_payment_history(:'clinic')='[]'::jsonb,'unexpected synthetic payment history');
select public.plan_request(:'clinic','clinic','monthly',repeat('a',48)) as request \gset
reset role;

update public.subscription_plans set published=true where code='clinic';

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000190',false);set role authenticated;
select pg_temp.assert_true((public.billing_request_read(:'request')->>'requested_by')='00000000-0000-0000-0000-000000000190','manager cannot read own billing request');
reset role;

set role service_role;
select public.ai_key_store_server('00000000-0000-0000-0000-000000000190','clinic',:'clinic','openai',repeat('c',24),repeat('n',16)) as connection \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000190',false);set role authenticated;
select pg_temp.assert_true(exists(
 select 1 from jsonb_array_elements(public.ai_dashboard(:'clinic')->'connections') x
 where x->>'id'=:'connection' and (x->>'can_manage')::boolean
),'explicit manager cannot manage clinic AI key');
reset role;

-- Revocation closes management on the next call, while ordinary shared-key membership remains separate.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'manage_grant','Synthetic workspace management revocation');
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-000000000190',false);set role authenticated;
select pg_temp.assert_true(public.workspace_management_status(:'clinic')=false,'revoked workspace manager still projected');
select pg_temp.assert_true(exists(
 select 1 from jsonb_array_elements(public.ai_dashboard(:'clinic')->'connections') x
 where x->>'id'=:'connection' and not (x->>'can_manage')::boolean
),'revoked manager retained AI management or lost ordinary shared-key membership');
select pg_temp.expect_error(format('select public.clinic_team_snapshot(%L)',:'clinic'),'workspace_manage_required');
select pg_temp.expect_error(format('select public.ai_connection_disable(%L)',:'connection'),'owner_required');
select pg_temp.expect_error(format('select public.plan_payment_history(%L)',:'clinic'),'payment_history_denied');
reset role;

-- Personal workspace ownership is its own management authority; no self-grant is required.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',false);set role authenticated;
select public.personal_workspace_create() as personal \gset
select pg_temp.assert_true(public.workspace_management_status(:'personal'),'personal owner not projected as manager');
select public.plan_request(:'personal','individual','monthly',repeat('b',48));
reset role;
