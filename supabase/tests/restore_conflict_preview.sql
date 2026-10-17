-- Synthetic, identifier-only conflict preview. Never imports backup rows.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select count(*) as patients_before from public.vet_patients where clinic_id=:'clinic' \gset

insert into public.clinics(id,name,created_by)
values('00000000-0000-0000-0000-000000000350','Synthetic foreign restore clinic','00000000-0000-0000-0000-000000000150')
on conflict(id) do nothing;
insert into public.vet_owners(id,clinic_id,name,created_by)
values('00000000-0000-0000-0000-000000000351','00000000-0000-0000-0000-000000000350','Foreign synthetic owner','00000000-0000-0000-0000-000000000150')
on conflict(id) do nothing;
insert into public.vet_patients(id,clinic_id,name,species,sex,owner_id,created_by)
values('00000000-0000-0000-0000-000000000352','00000000-0000-0000-0000-000000000350','Foreign synthetic patient','canino','sin especificar','00000000-0000-0000-0000-000000000351','00000000-0000-0000-0000-000000000150')
on conflict(id) do nothing;

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000194','synthetic-conflicts@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000194','admin')
on conflict(clinic_id,user_id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000194','backup.restore',null,clock_timestamp()+interval '1 day','Synthetic restore conflicts') as restore_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000194','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic restore conflict authority') as manage_grant \gset
reset role;

select id as existing_patient from public.vet_patients where clinic_id=:'clinic' order by id limit 1 \gset

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',false);set role authenticated;
select public.restore_preview_stage(
 :'clinic','vetdosis-operational-backup',1,repeat('c',64),
 clock_timestamp()-interval '1 hour',
 '{"vet_patients":3,"clinic_tasks":1}'::jsonb
) as stage \gset

select public.restore_preview_conflicts(
 :'clinic',
 (:'stage'::jsonb->>'stage_id')::uuid,
 repeat('c',64),
 repeat('d',64),
 jsonb_build_object(
   'vet_patients',jsonb_build_array(:'existing_patient','00000000-0000-0000-0000-000000000299','00000000-0000-0000-0000-000000000352'),
   'clinic_tasks',jsonb_build_array('00000000-0000-0000-0000-000000000298')
 )
) as conflicts \gset

select pg_temp.assert_true((:'conflicts'::jsonb->>'imports_applied')::boolean=false,'conflict preview claimed imports');
select pg_temp.assert_true((:'conflicts'::jsonb->>'incoming')::int=4,'incoming count mismatch');
select pg_temp.assert_true((:'conflicts'::jsonb->>'existing')::int=1,'existing count mismatch');
select pg_temp.assert_true((:'conflicts'::jsonb->>'foreign_conflict')::int=1,'foreign identity conflict missing');
select pg_temp.assert_true((:'conflicts'::jsonb->>'new')::int=2,'new count mismatch');
select pg_temp.assert_true((:'conflicts'::jsonb->'tables'->'vet_patients'->>'existing')::int=1,'patient conflict missing');
select pg_temp.assert_true((:'conflicts'::jsonb->'tables'->'vet_patients'->>'foreign_conflict')::int=1,'cross-workspace patient collision missing');
select pg_temp.assert_true(
 (public.restore_preview_get(:'clinic')->'stage'->'conflicts'->>'manifest_sha256')=repeat('d',64),
 'stored conflict report missing'
);

select pg_temp.expect_error(
 format($q$select public.restore_preview_conflicts(%L,%L::uuid,%L,%L,'{"auth_users":[]}'::jsonb)$q$,
  :'clinic',:'stage'::jsonb->>'stage_id',repeat('c',64),repeat('e',64)),
 'restore_manifest_invalid'
);
select pg_temp.expect_error(
 format($q$select public.restore_preview_conflicts(%L,%L::uuid,%L,%L,'{"vet_patients":[]}'::jsonb)$q$,
  :'clinic',:'stage'::jsonb->>'stage_id',repeat('f',64),repeat('e',64)),
 'restore_archive_changed'
);
select pg_temp.expect_error(
 format($q$select public.restore_preview_conflicts(%L,%L::uuid,%L,%L,'{"vet_patients":["not-a-uuid"]}'::jsonb)$q$,
  :'clinic',:'stage'::jsonb->>'stage_id',repeat('c',64),repeat('e',64)),
 'restore_manifest_invalid'
);
reset role;

-- Identifier comparison must not mutate operational rows.
select pg_temp.assert_true((select count(*) from public.vet_patients where clinic_id=:'clinic')=:'patients_before','conflict preview changed patient rows');

-- Revocation blocks future comparisons.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'restore_grant','Synthetic conflict preview revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_preview_conflicts(%L,%L::uuid,%L,%L,'{"vet_patients":[]}'::jsonb)$q$,
  :'clinic',:'stage'::jsonb->>'stage_id',repeat('c',64),repeat('e',64)),
 'backup_restore_required'
);
reset role;
