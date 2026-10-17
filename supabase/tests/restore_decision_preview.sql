-- Synthetic restore decision simulation. No backup row is imported.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as existing_patient from public.vet_patients where clinic_id=:'clinic' order by id limit 1 \gset
select id as global_template from public.form_templates where clinic_id is null order by id limit 1 \gset
select id as global_template_version from public.form_template_versions where clinic_id is null and template_id=:'global_template'::uuid order by version,id limit 1 \gset
select count(*) as patients_before from public.vet_patients where clinic_id=:'clinic' \gset

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000195','synthetic-restore-plan@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000195','admin')
on conflict(clinic_id,user_id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000195','backup.restore',null,clock_timestamp()+interval '1 day','Synthetic restore plan') as restore_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000195','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic restore plan authority') as manage_grant \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000195',false);set role authenticated;
-- Snapshot under the same authenticated role used for the final assertion so RLS
-- cannot make a read-only preview look like it changed operational rows.
select count(*) as patients_before from public.vet_patients where clinic_id=:'clinic' \gset
select public.restore_preview_stage(
 :'clinic','vetdosis-operational-backup',1,repeat('1',64),
 clock_timestamp()-interval '1 hour',
 '{"vet_owners":1,"vet_patients":3,"form_templates":1,"form_template_versions":1,"lotes_inventario":1,"clinic_appointments":1}'::jsonb
) as stage \gset

select public.restore_preview_conflicts(
 :'clinic',
 (:'stage'::jsonb->>'stage_id')::uuid,
 repeat('1',64),
 repeat('2',64),
 jsonb_build_object(
  'vet_owners',jsonb_build_array('00000000-0000-0000-0000-000000000301'),
  'vet_patients',jsonb_build_array(:'existing_patient','00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000352'),
  'form_templates',jsonb_build_array(:'global_template'),
  'form_template_versions',jsonb_build_array(:'global_template_version'),
  'lotes_inventario',jsonb_build_array('00000000-0000-0000-0000-000000000303'),
  'clinic_appointments',jsonb_build_array('00000000-0000-0000-0000-000000000304')
 )
) as conflicts \gset

select public.restore_preview_plan(
 :'clinic',
 (:'stage'::jsonb->>'stage_id')::uuid,
 repeat('1',64),
 repeat('2',64),
 repeat('3',64),
 jsonb_build_object(
  'vet_owners',jsonb_build_object(
   '00000000-0000-0000-0000-000000000301','[]'::jsonb
  ),
  'vet_patients',jsonb_build_object(
   :'existing_patient','[]'::jsonb,
   '00000000-0000-0000-0000-000000000302',jsonb_build_array(jsonb_build_object('table','vet_owners','id','00000000-0000-0000-0000-000000000301')),
   '00000000-0000-0000-0000-000000000352','[]'::jsonb
  ),
  'form_templates',jsonb_build_object(
   :'global_template','[]'::jsonb
  ),
  'form_template_versions',jsonb_build_object(
   :'global_template_version',jsonb_build_array(jsonb_build_object('table','form_templates','id',:'global_template'))
  ),
  'lotes_inventario',jsonb_build_object(
   '00000000-0000-0000-0000-000000000303',jsonb_build_array(jsonb_build_object('table','inventario','id','00000000-0000-0000-0000-000000000399'))
  ),
  'clinic_appointments',jsonb_build_object(
   '00000000-0000-0000-0000-000000000304',jsonb_build_array(
    jsonb_build_object('table','vet_patients','id','00000000-0000-0000-0000-000000000302'),
    jsonb_build_object('table','clinic_members','id','00000000-0000-0000-0000-000000000398')
   )
  )
 )
) as plan \gset

select pg_temp.assert_true((:'plan'::jsonb->>'imports_applied')::boolean=false,'decision preview claimed imports');
select pg_temp.assert_true((:'plan'::jsonb->>'create_candidate')::int=2,'create count mismatch');
select pg_temp.assert_true((:'plan'::jsonb->>'keep_existing')::int=3,'keep count mismatch');
select pg_temp.assert_true((:'plan'::jsonb->>'blocked_missing_dependency')::int=1,'blocked count mismatch');
select pg_temp.assert_true((:'plan'::jsonb->>'blocked_foreign_identity')::int=1,'foreign identity block mismatch');
select pg_temp.assert_true((:'plan'::jsonb->>'manual_review')::int=1,'manual count mismatch');
select pg_temp.assert_true((:'plan'::jsonb->'policy'->>'overwrite')::boolean=false,'plan enabled overwrite');
select pg_temp.assert_true((:'plan'::jsonb->'policy'->>'merge')::boolean=false,'plan enabled merge');
select pg_temp.assert_true((:'plan'::jsonb->'tables'->'vet_patients'->>'keep_existing')::int=1,'existing patient not preserved');
select pg_temp.assert_true((:'plan'::jsonb->'tables'->'vet_patients'->>'blocked_foreign_identity')::int=1,'foreign patient identity not blocked');
select pg_temp.assert_true((:'plan'::jsonb->'tables'->'form_templates'->>'keep_existing')::int=1,'global template not preserved');
select pg_temp.assert_true((:'plan'::jsonb->'tables'->'form_template_versions'->>'keep_existing')::int=1,'global template version not preserved');
select pg_temp.assert_true((:'plan'::jsonb->'tables'->'lotes_inventario'->>'blocked_missing_dependency')::int=1,'missing inventory parent not blocked');
select pg_temp.assert_true((:'plan'::jsonb->'tables'->'clinic_appointments'->>'manual_review')::int=1,'missing staff reference not manual');

select pg_temp.expect_error(
 format($q$select public.restore_preview_plan(%L,%L::uuid,%L,%L,%L,'{"vet_owners":{},"vet_patients":{},"form_templates":{},"form_template_versions":{},"lotes_inventario":{},"clinic_appointments":{}}'::jsonb)$q$,
  :'clinic',:'stage'::jsonb->>'stage_id',repeat('1',64),repeat('2',64),repeat('4',64)),
 'restore_dependencies_changed'
);

select pg_temp.assert_true((select count(*) from public.vet_patients where clinic_id=:'clinic')=:'patients_before','decision simulation changed patient rows');
reset role;

-- Losing restore authority invalidates the simulation path immediately.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'restore_grant','Synthetic restore plan revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000195',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_preview_plan(%L,%L::uuid,%L,%L,%L,'{}'::jsonb)$q$,
  :'clinic',:'stage'::jsonb->>'stage_id',repeat('1',64),repeat('2',64),repeat('3',64)),
 'backup_restore_required'
);
reset role;
