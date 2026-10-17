-- Synthetic backup scopes only. No real clinical content.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset

-- A visual administrator receives nothing automatically.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'backup_export_required');
select pg_temp.assert_true(not(public.backup_workspace(:'clinic')->'exports'->>'clinic')::boolean,'visual role opened clinic backup');
reset role;

-- The responsible grants explicit export and workspace administration.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','backup.export',null,clock_timestamp()+interval '1 day','Synthetic backup export') as export_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'backup_export_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic workspace authority') as manage_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true((public.backup_workspace(:'clinic')->'exports'->>'clinic')::boolean,'explicit clinic backup absent');
select pg_temp.assert_true((public.clinic_export(:'clinic')::jsonb->>'format')='vetdosis-operational-backup','clinic backup format mismatch');
select pg_temp.assert_true(not(public.backup_workspace(:'clinic')->>'statistics')::boolean,'backup permissions leaked statistics');
select pg_temp.expect_error(format('select public.clinic_statistics(%L)',:'clinic'),'sales_read_required');
reset role;

-- Statistics remain a separate read capability.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000180','sales.read',null,clock_timestamp()+interval '1 day','Synthetic statistics read');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true((public.backup_workspace(:'clinic')->>'statistics')::boolean,'sales read did not open statistics');
select pg_temp.assert_true(public.clinic_statistics(:'clinic') ? 'sales','statistics payload missing');reset role;

-- A personal export belongs only to its owner and contains an allowlist.
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000181','synthetic-personal-owner@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select public.personal_workspace_create() as personal \gset
reset role;
insert into public.dose_personal_entries(clinic_id,user_id,payload,state) values(:'personal','00000000-0000-0000-0000-000000000181','{"source":"synthetic"}','personal');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',false);set role authenticated;
select public.personal_export(:'personal')::jsonb as personal_backup \gset
select pg_temp.assert_true((:'personal_backup'::jsonb->>'format')='vetdosis-personal-backup','personal format mismatch');
select pg_temp.assert_true(jsonb_array_length(:'personal_backup'::jsonb->'tables'->'dose_personal_entries')=1,'own dose absent');
select pg_temp.assert_true(not(:'personal_backup'::jsonb->'tables' ?| array['vet_patients','vet_owners','clinical_cases','hospital_stays','form_documents','form_signatures']),'personal backup exposed clinical tables');
select pg_temp.assert_true((public.backup_workspace(:'personal')->'exports'->>'personal')::boolean and not(public.backup_workspace(:'personal')->'exports'->>'clinic')::boolean,'personal scopes mismatch');
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.expect_error(format('select public.personal_export(%L)',:'personal'),'personal_owner_required');reset role;
set role anon;
select pg_temp.expect_error(format('select public.backup_workspace(%L)',:'clinic'),'permission denied');
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'permission denied');reset role;

-- Revocation closes navigation and export on the next server call.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'export_grant','Synthetic backup revocation');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000180',false);set role authenticated;
select pg_temp.assert_true(not(public.app_module_workspace(:'clinic')->'modules'->>'backup')::boolean,'revoked backup remained in navigation');
select pg_temp.expect_error(format('select public.clinic_export(%L)',:'clinic'),'backup_export_required');reset role;
