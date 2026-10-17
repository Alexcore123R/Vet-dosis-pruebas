-- Restore preview staging is metadata-only and synthetic.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select count(*) as patients_before from public.vet_patients where clinic_id=:'clinic' \gset

insert into auth.users(id,email,email_confirmed_at)
values('00000000-0000-0000-0000-000000000193','synthetic-restore@example.test',now())
on conflict(id) do nothing;
insert into public.clinic_members(clinic_id,user_id,role)
values(:'clinic','00000000-0000-0000-0000-000000000193','admin')
on conflict(clinic_id,user_id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000193',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_preview_stage(%L,'vetdosis-operational-backup',1,repeat('a',64),clock_timestamp(),'{"vet_patients":2}'::jsonb)$q$,:'clinic'),
 'backup_restore_required'
);
reset role;

-- Restore permission alone is deliberately insufficient.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000193','backup.restore',null,clock_timestamp()+interval '1 day','Synthetic restore preview') as restore_grant \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000193',false);set role authenticated;
select pg_temp.expect_error(
 format($q$select public.restore_preview_stage(%L,'vetdosis-operational-backup',1,repeat('a',64),clock_timestamp(),'{"vet_patients":2}'::jsonb)$q$,:'clinic'),
 'backup_restore_required'
);
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000193','workspace.manage',null,clock_timestamp()+interval '1 day','Synthetic restore workspace authority') as manage_grant \gset
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000193',false);set role authenticated;
select public.restore_preview_stage(
 :'clinic','vetdosis-operational-backup',1,repeat('a',64),
 clock_timestamp()-interval '1 day',
 '{"vet_patients":2,"vet_owners":1,"clinical_cases":3}'::jsonb
) as first_stage \gset
select pg_temp.assert_true((:'first_stage'::jsonb->>'imports_applied')::boolean=false,'preview claimed imports were applied');
select pg_temp.assert_true((:'first_stage'::jsonb->'table_counts'->>'clinical_cases')::int=3,'preview counts changed');
select pg_temp.assert_true((:'first_stage'::jsonb->>'expires_at')::timestamptz>(:'first_stage'::jsonb->>'created_at')::timestamptz+interval '13 days 23 hours','preview TTL too short');

select public.restore_preview_stage(
 :'clinic','vetdosis-operational-backup',1,repeat('b',64),
 clock_timestamp()-interval '2 hours',
 '{"vet_patients":4}'::jsonb
) as second_stage \gset
select pg_temp.assert_true(:'first_stage'::jsonb->>'stage_id'<>:'second_stage'::jsonb->>'stage_id','replacement reused stage id');
select pg_temp.assert_true(public.restore_preview_get(:'clinic')->'stage'->>'archive_sha256'=repeat('b',64),'latest preview not authoritative');

select pg_temp.expect_error(
 format($q$select public.restore_preview_stage(%L,'unknown-backup',1,repeat('a',64),clock_timestamp(),'{"vet_patients":1}'::jsonb)$q$,:'clinic'),
 'restore_format_unsupported'
);
select pg_temp.expect_error(
 format($q$select public.restore_preview_stage(%L,'vetdosis-operational-backup',1,'bad-hash',clock_timestamp(),'{"vet_patients":1}'::jsonb)$q$,:'clinic'),
 'restore_hash_required'
);
select pg_temp.expect_error(
 format($q$select public.restore_preview_stage(%L,'vetdosis-operational-backup',1,repeat('a',64),clock_timestamp()+interval '1 hour','{"vet_patients":1}'::jsonb)$q$,:'clinic'),
 'restore_source_time_invalid'
);
select pg_temp.expect_error(
 format($q$select public.restore_preview_stage(%L,'vetdosis-operational-backup',1,repeat('a',64),clock_timestamp(),'{"vet_patients":-1}'::jsonb)$q$,:'clinic'),
 'restore_counts_invalid'
);

select public.restore_preview_discard(:'clinic',(:'second_stage'::jsonb->>'stage_id')::uuid);
select pg_temp.assert_true(public.restore_preview_get(:'clinic')->'stage'='null'::jsonb,'discard left active preview');
reset role;

-- Staging never touches operational patient rows.
select pg_temp.assert_true((select count(*) from public.vet_patients where clinic_id=:'clinic')=:'patients_before','preview changed patient rows');

-- Revocation applies immediately.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'restore_grant','Synthetic restore revocation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000193',false);set role authenticated;
select pg_temp.expect_error(format('select public.restore_preview_get(%L)',:'clinic'),'backup_restore_required');
reset role;

set role anon;
select pg_temp.expect_error(format('select public.restore_preview_get(%L)',:'clinic'),'permission denied');
reset role;
