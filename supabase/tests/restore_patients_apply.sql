-- Synthetic create-only patient restore.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000198','synthetic-patient-restore@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000198','admin')
on conflict(clinic_id,user_id) do update set role=excluded.role;

-- Deterministic same-clinic owner and existing patient.
insert into public.vet_owners(id,clinic_id,name,created_by)
values('00000000-0000-0000-0000-000000000690',:'clinic','Patient restore owner','00000000-0000-0000-0000-000000000150')
on conflict(id) do nothing;
insert into public.vet_patients(id,clinic_id,name,species,breed,sex,birth_date,owner_id,created_by)
values(
 '00000000-0000-0000-0000-000000000692',:'clinic','Existing patient original',
 'canino','mestizo','hembra','2020-01-02','00000000-0000-0000-0000-000000000690',
 '00000000-0000-0000-0000-000000000150'
)
on conflict(id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000198','backup.restore',null,clock_timestamp()+interval '1 day','Synthetic patient restore') as restore_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000198','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic patient restore authority') as manage_grant \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000198',false);set role authenticated;
select public.restore_preview_stage(:'clinic','vetdosis-operational-backup',1,repeat('7',64),'2026-01-02T00:00:00Z','{"vet_patients":2}'::jsonb) as stage \gset
select public.restore_preview_conflicts(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('7',64),repeat('8',64),
 '{"vet_patients":["00000000-0000-0000-0000-000000000691","00000000-0000-0000-0000-000000000692"]}'::jsonb
);
select public.restore_preview_plan(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('7',64),repeat('8',64),repeat('9',64),
 jsonb_build_object(
  'vet_patients',jsonb_build_object(
   '00000000-0000-0000-0000-000000000691',
   jsonb_build_array(jsonb_build_object('table','vet_owners','id','00000000-0000-0000-0000-000000000690')),
   '00000000-0000-0000-0000-000000000692',
   jsonb_build_array(jsonb_build_object('table','vet_owners','id','00000000-0000-0000-0000-000000000690'))
  )
 )
);
select public.restore_prepare_patients(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('7',64),
 jsonb_build_array(
  jsonb_build_object(
   'id','00000000-0000-0000-0000-000000000691','clinic_id',:'clinic',
   'name','Restored synthetic patient','species','felino','breed','doméstico',
   'sex','macho','birth_date','2021-03-04','owner_id','00000000-0000-0000-0000-000000000690',
   'source_created_by','00000000-0000-0000-0000-000000000150','source_created_at','2025-02-03T04:05:06Z'
  ),
  jsonb_build_object(
   'id','00000000-0000-0000-0000-000000000692','clinic_id',:'clinic',
   'name','Must stay unchanged','species','canino','breed','otro','sex','macho',
   'owner_id','00000000-0000-0000-0000-000000000690'
  )
 )
) as prepared \gset
select public.restore_preview_preflight(:'clinic',(:'stage'::jsonb->>'stage_id')::uuid,repeat('7',64),repeat('8',64),repeat('9',64)) as preflight \gset
select pg_temp.expect_error(format('select public.restore_apply_patients(%L,%L::uuid,null,%L)',:'clinic',:'stage'::jsonb->>'stage_id',:'prepared'::jsonb->>'payload_sha256'),'restore_preflight_required');
select pg_temp.expect_error(format('select public.restore_apply_patients(%L,%L::uuid,%L::uuid,null)',:'clinic',:'stage'::jsonb->>'stage_id',:'preflight'::jsonb->>'preflight_id'),'restore_patient_payload_changed');
reset role;
delete from private.backup_restore_test_targets where clinic_id=:'clinic';
set role authenticated;
select pg_temp.expect_error(format('select public.restore_apply_patients(%L,%L::uuid,%L::uuid,%L)',:'clinic',:'stage'::jsonb->>'stage_id',:'preflight'::jsonb->>'preflight_id',:'prepared'::jsonb->>'payload_sha256'),'restore_test_target_required');
reset role;
insert into private.backup_restore_test_targets(clinic_id,expires_at) values(:'clinic',clock_timestamp()+interval '1 day');
set role authenticated;
select public.restore_apply_patients(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,
 (:'preflight'::jsonb->>'preflight_id')::uuid,
 :'prepared'::jsonb->>'payload_sha256'
) as applied \gset

select pg_temp.assert_true((:'applied'::jsonb->>'imports_applied')::boolean,'patient restore not applied');
select pg_temp.assert_true((:'applied'::jsonb->>'created')::int=1,'wrong patient create count');
select pg_temp.assert_true((:'applied'::jsonb->>'kept_existing')::int=1,'wrong patient keep count');

reset role;
select pg_temp.assert_true(
 (select name from public.vet_patients where id='00000000-0000-0000-0000-000000000692')='Existing patient original',
 'existing patient overwritten'
);
select pg_temp.assert_true(
 exists(
  select 1 from public.vet_patients
  where id='00000000-0000-0000-0000-000000000691'
   and clinic_id=:'clinic'
   and owner_id='00000000-0000-0000-0000-000000000690'
   and created_by='00000000-0000-0000-0000-000000000198'
   and name='Restored synthetic patient'
 ),
 'new patient missing or wrong attribution'
);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000198',false);set role authenticated;

-- Successful retry is idempotent.
select public.restore_apply_patients(
 :'clinic',(:'stage'::jsonb->>'stage_id')::uuid,
 (:'preflight'::jsonb->>'preflight_id')::uuid,
 :'prepared'::jsonb->>'payload_sha256'
) as retry \gset
select pg_temp.assert_true(:'retry'::jsonb=:'applied'::jsonb,'idempotent patient retry changed result');
reset role;

-- Owner dependency drift is checked before any patient insert.
insert into public.vet_owners(id,clinic_id,name,created_by)
values('00000000-0000-0000-0000-000000000693',:'clinic','Temporary restore owner','00000000-0000-0000-0000-000000000150');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000198',false);set role authenticated;
select public.restore_preview_stage(:'clinic','vetdosis-operational-backup',1,repeat('a',64),'2026-01-02T00:00:00Z','{"vet_patients":1}'::jsonb) as drift_stage \gset
select public.restore_preview_conflicts(
 :'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),
 '{"vet_patients":["00000000-0000-0000-0000-000000000694"]}'::jsonb
);
select public.restore_preview_plan(
 :'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),repeat('c',64),
 '{"vet_patients":{"00000000-0000-0000-0000-000000000694":[{"table":"vet_owners","id":"00000000-0000-0000-0000-000000000693"}]}}'::jsonb
);
select public.restore_prepare_patients(
 :'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),
 jsonb_build_array(jsonb_build_object(
  'id','00000000-0000-0000-0000-000000000694','clinic_id',:'clinic',
  'name','Atomic patient','species','canino','breed','','sex','sin especificar',
  'owner_id','00000000-0000-0000-0000-000000000693'
 ))
) as drift_prepared \gset
select public.restore_preview_preflight(:'clinic',(:'drift_stage'::jsonb->>'stage_id')::uuid,repeat('a',64),repeat('b',64),repeat('c',64)) as drift_preflight \gset
reset role;
delete from public.vet_owners where id='00000000-0000-0000-0000-000000000693';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000198',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_apply_patients(%L,%L::uuid,%L::uuid,%L)$q$,
  :'clinic',:'drift_stage'::jsonb->>'stage_id',:'drift_preflight'::jsonb->>'preflight_id',:'drift_prepared'::jsonb->>'payload_sha256'),
 'restore_patient_owner_state_drift'
);
reset role;
select pg_temp.assert_true(
 not exists(select 1 from public.vet_patients where id='00000000-0000-0000-0000-000000000694'),
 'patient restore partially committed before owner drift failure'
);

-- Applying owners in a stage invalidates that stage for patient apply: callers must re-stage.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000198',false);set role authenticated;
select public.restore_preview_stage(:'clinic','vetdosis-operational-backup',1,repeat('d',64),'2026-01-02T00:00:00Z','{"vet_owners":1,"vet_patients":1}'::jsonb) as mixed_stage \gset
select public.restore_preview_conflicts(
 :'clinic',(:'mixed_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),repeat('e',64),
 '{"vet_owners":["00000000-0000-0000-0000-000000000695"],"vet_patients":["00000000-0000-0000-0000-000000000696"]}'::jsonb
);
select public.restore_preview_plan(
 :'clinic',(:'mixed_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),repeat('e',64),repeat('f',64),
 '{"vet_owners":{"00000000-0000-0000-0000-000000000695":[]},"vet_patients":{"00000000-0000-0000-0000-000000000696":[{"table":"vet_owners","id":"00000000-0000-0000-0000-000000000695"}]}}'::jsonb
);
select public.restore_prepare_owners(
 :'clinic',(:'mixed_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),
 jsonb_build_array(jsonb_build_object(
  'id','00000000-0000-0000-0000-000000000695','clinic_id',:'clinic','name','Owner requiring fresh patient stage'
 ))
) as mixed_owner_payload \gset
select public.restore_preview_preflight(:'clinic',(:'mixed_stage'::jsonb->>'stage_id')::uuid,repeat('d',64),repeat('e',64),repeat('f',64)) as mixed_preflight \gset
select public.restore_apply_owners(
 :'clinic',(:'mixed_stage'::jsonb->>'stage_id')::uuid,
 (:'mixed_preflight'::jsonb->>'preflight_id')::uuid,
 :'mixed_owner_payload'::jsonb->>'payload_sha256'
);
select pg_temp.expect_error(
 format(
  $q$select public.restore_prepare_patients(%L,%L::uuid,%L,jsonb_build_array(jsonb_build_object(
   'id','00000000-0000-0000-0000-000000000696','clinic_id',%L,'name','Needs restage',
   'species','canino','breed','','sex','hembra','owner_id','00000000-0000-0000-0000-000000000695'
  )))$q$,
  :'clinic',:'mixed_stage'::jsonb->>'stage_id',repeat('d',64),:'clinic'
 ),
 'restore_patient_restage_required'
);
reset role;
