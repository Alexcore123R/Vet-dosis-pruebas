-- Synthetic application preflight. Still no restore/import operation exists.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select count(*) as owners_before from public.vet_owners where clinic_id=:'clinic' \gset

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000196','synthetic-preflight@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000196','admin')
on conflict(clinic_id,user_id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000196','backup.restore',null,clock_timestamp()+interval '1 day','Synthetic restore preflight') as restore_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000196','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic restore preflight authority') as manage_grant \gset
reset role;

-- Clean plan: one new owner with no dependencies is applicable.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000196',false);set role authenticated;
select public.restore_preview_stage(
 :'clinic','vetdosis-operational-backup',1,repeat('a',64),
 clock_timestamp()-interval '1 hour',
 '{"vet_owners":1}'::jsonb
) as clean_stage \gset

select public.restore_preview_conflicts(
 :'clinic',(:'clean_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),
 '{"vet_owners":["00000000-0000-0000-0000-000000000401"]}'::jsonb
);

select public.restore_preview_plan(
 :'clinic',(:'clean_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),repeat('c',64),
 '{"vet_owners":{"00000000-0000-0000-0000-000000000401":[]}}'::jsonb
);

select public.restore_preview_preflight(
 :'clinic',(:'clean_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),repeat('c',64)
) as clean_preflight \gset

select pg_temp.assert_true((:'clean_preflight'::jsonb->>'applicable')::boolean,'clean plan was not applicable');
select pg_temp.assert_true((:'clean_preflight'::jsonb->>'imports_applied')::boolean=false,'preflight claimed imports');
select pg_temp.assert_true(jsonb_array_length(:'clean_preflight'::jsonb->'blockers')=0,'clean preflight has blockers');
select pg_temp.assert_true((:'clean_preflight'::jsonb->>'checked_entries')::int=1,'clean preflight did not recheck row');
select pg_temp.assert_true((:'clean_preflight'::jsonb->>'valid_until')::timestamptz>(:'clean_preflight'::jsonb->>'checked_at')::timestamptz+interval '14 minutes','preflight window too short');

-- Current state drift after the plan makes the same staged plan non-applicable.
reset role;
insert into public.vet_owners(id,clinic_id,name,created_by)
values('00000000-0000-0000-0000-000000000401',:'clinic','Synthetic drift owner','00000000-0000-0000-0000-000000000150');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000196',false);set role authenticated;
select public.restore_preview_preflight(
 :'clinic',(:'clean_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),repeat('c',64)
) as drift_preflight \gset
select pg_temp.assert_true(not(:'drift_preflight'::jsonb->>'applicable')::boolean,'state drift remained applicable');
select pg_temp.assert_true(exists(
 select 1 from jsonb_array_elements(:'drift_preflight'::jsonb->'blockers') b
 where b->>'code'='state_drift_now_exists'
),'state drift blocker missing');
reset role;
delete from public.vet_owners where id='00000000-0000-0000-0000-000000000401';

-- A plan that already contains unresolved decisions is not applicable.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000196',false);set role authenticated;
select public.restore_preview_stage(
 :'clinic','vetdosis-operational-backup',1,repeat('d',64),
 clock_timestamp()-interval '1 hour',
 '{"clinic_tasks":1}'::jsonb
) as blocked_stage \gset

select public.restore_preview_conflicts(
 :'clinic',(:'blocked_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),repeat('e',64),
 '{"clinic_tasks":["00000000-0000-0000-0000-000000000402"]}'::jsonb
);

select public.restore_preview_plan(
 :'clinic',(:'blocked_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),repeat('e',64),repeat('f',64),
 '{"clinic_tasks":{"00000000-0000-0000-0000-000000000402":[{"table":"clinic_members","id":"00000000-0000-0000-0000-000000000498"}]}}'::jsonb
);

select public.restore_preview_preflight(
 :'clinic',(:'blocked_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),repeat('e',64),repeat('f',64)
) as blocked_preflight \gset
select pg_temp.assert_true(not(:'blocked_preflight'::jsonb->>'applicable')::boolean,'manual-review plan became applicable');
select pg_temp.assert_true(exists(
 select 1 from jsonb_array_elements(:'blocked_preflight'::jsonb->'blockers') b
 where b->>'code'='manual_review'
),'manual-review blocker missing');

-- Hash linkage cannot be swapped after simulation.
select pg_temp.expect_error(
 format($q$select public.restore_preview_preflight(%L,%L::uuid,%L,%L,%L)$q$,
  :'clinic',:'blocked_stage'::jsonb->>'stage_id',repeat('0',64),repeat('e',64),repeat('f',64)),
 'restore_archive_changed'
);
reset role;

select pg_temp.assert_true((select count(*) from public.vet_owners where clinic_id=:'clinic')=:'owners_before','preflight changed operational owner rows');

-- Revocation invalidates preflight immediately.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'restore_grant','Synthetic preflight revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000196',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_preview_preflight(%L,%L::uuid,%L,%L,%L)$q$,
  :'clinic',:'blocked_stage'::jsonb->>'stage_id',repeat('d',64),repeat('e',64),repeat('f',64)),
 'backup_restore_required'
);
reset role;
