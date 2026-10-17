-- Synthetic create-only owner restore.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as existing_owner from public.vet_owners where clinic_id=:'clinic' order by id limit 1 \gset
select name as existing_name from public.vet_owners where id=:'existing_owner' \gset

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000197','synthetic-owner-restore@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000197','admin')
on conflict(clinic_id,user_id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000197','backup.restore',null,clock_timestamp()+interval '1 day','Synthetic owner restore') as restore_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000197','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic owner restore authority') as manage_grant \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000197',false);set role authenticated;
select public.restore_preview_stage(:'clinic','vetdosis-operational-backup',1,repeat('1',64),'2026-01-02T00:00:00Z','{"vet_owners":2}'::jsonb) as stage \gset
select public.restore_preview_conflicts(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('1',64),repeat('2',64),
 jsonb_build_object('vet_owners',jsonb_build_array(:'existing_owner','00000000-0000-0000-0000-000000000501'))
);
select public.restore_preview_plan(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('1',64),repeat('2',64),repeat('3',64),
 jsonb_build_object('vet_owners',jsonb_build_object(:'existing_owner','[]'::jsonb,'00000000-0000-0000-0000-000000000501','[]'::jsonb))
);
select public.restore_prepare_owners(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('1',64),
 jsonb_build_array(
  jsonb_build_object('id',:'existing_owner','clinic_id',:'clinic','name','Must stay unchanged'),
  jsonb_build_object('id','00000000-0000-0000-0000-000000000501','clinic_id',:'clinic','name','Restored synthetic owner','source_created_at','2025-02-03T04:05:06Z')
 )
) as prepared \gset
select pg_temp.expect_error(format('select public.restore_preview_preflight(%L,%L::uuid,null,%L,%L)',:'clinic',:'stage'::jsonb->>'stage_id',repeat('2',64),repeat('3',64)),'restore_archive_changed');
select pg_temp.expect_error(format('select public.restore_preview_preflight(%L,%L::uuid,%L,null,%L)',:'clinic',:'stage'::jsonb->>'stage_id',repeat('1',64),repeat('3',64)),'restore_conflicts_changed');
select pg_temp.expect_error(format('select public.restore_preview_preflight(%L,%L::uuid,%L,%L,null)',:'clinic',:'stage'::jsonb->>'stage_id',repeat('1',64),repeat('2',64)),'restore_dependencies_changed');
select public.restore_preview_preflight(:'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('1',64),repeat('2',64),repeat('3',64)) as preflight \gset
select pg_temp.expect_error(format('select public.restore_apply_owners(%L,%L::uuid,%L::uuid,%L)',:'clinic',:'stage'::jsonb->>'stage_id',:'preflight'::jsonb->>'preflight_id',:'prepared'::jsonb->>'payload_sha256'),'restore_test_target_required');
reset role;
insert into private.backup_restore_test_targets(clinic_id,expires_at) values(:'clinic',clock_timestamp()+interval '1 day');
set role authenticated;
select pg_temp.expect_error(format('select public.restore_apply_owners(%L,%L::uuid,null,%L)',:'clinic',:'stage'::jsonb->>'stage_id',:'prepared'::jsonb->>'payload_sha256'),'restore_preflight_required');
select pg_temp.expect_error(format('select public.restore_apply_owners(%L,%L::uuid,%L::uuid,null)',:'clinic',:'stage'::jsonb->>'stage_id',:'preflight'::jsonb->>'preflight_id'),'restore_owner_payload_changed');
select public.restore_apply_owners(:'clinic',(:'stage'::jsonb->>'stage_id')::uuid,(:'preflight'::jsonb->>'preflight_id')::uuid,:'prepared'::jsonb->>'payload_sha256') as applied \gset

select pg_temp.assert_true((:'applied'::jsonb->>'imports_applied')::boolean,'owner restore not applied');
select pg_temp.assert_true((:'applied'::jsonb->>'created')::int=1,'wrong owner create count');
select pg_temp.assert_true((:'applied'::jsonb->>'kept_existing')::int=1,'wrong owner keep count');

-- Verify operational rows outside RLS; the restore call itself already ran as authenticated.
reset role;
select pg_temp.assert_true((select name from public.vet_owners where id=:'existing_owner')=:'existing_name','existing owner overwritten');
select pg_temp.assert_true(exists(select 1 from public.vet_owners where id='00000000-0000-0000-0000-000000000501' and created_by='00000000-0000-0000-0000-000000000197'),'new owner missing or wrong attribution');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000197',false);set role authenticated;

-- Successful retry is idempotent.
select public.restore_apply_owners(:'clinic',(:'stage'::jsonb->>'stage_id')::uuid,(:'preflight'::jsonb->>'preflight_id')::uuid,:'prepared'::jsonb->>'payload_sha256') as retry \gset
select pg_temp.assert_true(:'retry'::jsonb=:'applied'::jsonb,'idempotent retry changed result');

-- Drift is checked for every owner before the first insert, so failure is atomic.
select public.restore_preview_stage(:'clinic','vetdosis-operational-backup',1,repeat('4',64),'2026-01-02T00:00:00Z','{"vet_owners":2}'::jsonb) as drift_stage \gset
select public.restore_preview_conflicts(
 :'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('4',64),repeat('5',64),
 '{"vet_owners":["00000000-0000-0000-0000-000000000502","00000000-0000-0000-0000-000000000503"]}'::jsonb
);
select public.restore_preview_plan(
 :'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('4',64),repeat('5',64),repeat('6',64),
 '{"vet_owners":{"00000000-0000-0000-0000-000000000502":[],"00000000-0000-0000-0000-000000000503":[]}}'::jsonb
);
select public.restore_prepare_owners(
 :'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('4',64),
 jsonb_build_array(
  jsonb_build_object('id','00000000-0000-0000-0000-000000000502','clinic_id',:'clinic','name','Atomic A'),
  jsonb_build_object('id','00000000-0000-0000-0000-000000000503','clinic_id',:'clinic','name','Atomic B')
 )
) as drift_prepared \gset
select public.restore_preview_preflight(:'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('4',64),repeat('5',64),repeat('6',64)) as drift_preflight \gset
reset role;
insert into public.vet_owners(id,clinic_id,name,created_by)
values('00000000-0000-0000-0000-000000000503',:'clinic','Concurrent owner','00000000-0000-0000-0000-000000000150');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000197',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_apply_owners(%L,%L::uuid,%L::uuid,%L)$q$,
  :'clinic',:'drift_stage'::jsonb->>'stage_id',:'drift_preflight'::jsonb->>'preflight_id',:'drift_prepared'::jsonb->>'payload_sha256'),
 'restore_owner_state_drift'
);
select pg_temp.assert_true(
 not exists(select 1 from public.vet_owners where id='00000000-0000-0000-0000-000000000502'),
 'owner restore partially committed before drift failure'
);
reset role;
delete from public.vet_owners where id='00000000-0000-0000-0000-000000000503';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000197',false);set role authenticated;

-- Payload IDs cannot diverge from the verified manifest.
select pg_temp.expect_error(
 format($q$select public.restore_prepare_owners(%L,%L::uuid,%L,jsonb_build_array(jsonb_build_object('id','00000000-0000-0000-0000-000000000599','clinic_id',%L,'name','Wrong')))$q$,
  :'clinic',:'drift_stage'::jsonb->>'stage_id',repeat('4',64),:'clinic'),
 'restore_owner_payload_changed'
);
reset role;
