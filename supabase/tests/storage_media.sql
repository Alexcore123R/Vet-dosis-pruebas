-- Synthetic private Storage policy checks. No real files are uploaded.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;

select id as clinic from public.clinics where name='Synthetic clinical permission A' \gset
select id as case_id,patient_id as patient from public.clinical_cases where clinic_id=:'clinic' and title='Synthetic case' \gset
select created_at as member_since from public.clinic_members
where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000111' \gset

-- Give the synthetic actor only the explicit grants needed by this isolated Storage test.
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select :'clinic','00000000-0000-0000-0000-000000000111',:'member_since','patient.read',
 '00000000-0000-0000-0000-000000000111',clock_timestamp()+interval '1 day','Synthetic Storage read'
where private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000111','patient.read') is null;

insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select :'clinic','00000000-0000-0000-0000-000000000111',:'member_since','patient.write',
 '00000000-0000-0000-0000-000000000111',clock_timestamp()+interval '1 day','Synthetic Storage photo write'
where private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000111','patient.write') is null;

insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select :'clinic','00000000-0000-0000-0000-000000000111',:'member_since','clinical.read',
 '00000000-0000-0000-0000-000000000111',clock_timestamp()+interval '1 day','Synthetic Storage clinical read'
where private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000111','clinical.read') is null;

insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
values(
 :'clinic','00000000-0000-0000-0000-000000000111',:'member_since','clinical.attach',
 '00000000-0000-0000-0000-000000000111',clock_timestamp()+interval '1 day','Synthetic Storage attachment write'
);

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;

select pg_temp.assert_true(
 private.storage_patient_photo_allowed(:'clinic'::text||'/'||:'patient'::text||'/photo.png',false),
 'patient photo should be readable with patient.read'
);
select pg_temp.assert_true(
 private.storage_patient_photo_allowed(:'clinic'::text||'/'||:'patient'::text||'/photo.webp',true),
 'patient photo should be writable with patient.write'
);
select pg_temp.assert_true(
 not private.storage_patient_photo_allowed(:'clinic'::text||'/'||:'patient'::text||'/avatar.png',true),
 'patient photo path must use the fixed photo slot'
);

insert into storage.objects(bucket_id,name,metadata)
values('patient-photos',:'clinic'::text||'/'||:'patient'::text||'/photo.png','{"mimetype":"image/png","size":1200}'::jsonb);

select pg_temp.assert_true(
 (select count(*)=1 from storage.objects where bucket_id='patient-photos'),
 'authorized actor cannot read own clinic patient photo'
);

select set_config('test.attachment',:'clinic'::text||'/'||:'case_id'::text||'/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.pdf',false);
insert into storage.objects(bucket_id,name,metadata)
values('clinical-attachments',current_setting('test.attachment'),'{"mimetype":"application/pdf","size":4096}'::jsonb);

select pg_temp.assert_true(
 (select count(*)=1 from storage.objects where bucket_id='clinical-attachments' and name=current_setting('test.attachment')),
 'authorized actor cannot read registered clinical attachment'
);

select pg_temp.expect_error(
 format(
  $q$insert into storage.objects(bucket_id,name) values('clinical-attachments',%L)$q$,
  :'clinic'::text||'/'||:'case_id'::text||'/not-a-uuid.pdf'
 ),
 'row-level security'
);
reset role;

-- A different authenticated user cannot see either private object and cannot upload.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000113',false);
set role authenticated;
select pg_temp.assert_true(
 (select count(*)=0 from storage.objects where bucket_id='patient-photos'),
 'unprivileged actor can read patient photo'
);
select pg_temp.assert_true(
 (select count(*)=0 from storage.objects where bucket_id='clinical-attachments'),
 'unprivileged actor can read clinical attachment'
);
select pg_temp.expect_error(
 format(
  $q$insert into storage.objects(bucket_id,name) values('patient-photos',%L)$q$,
  :'clinic'::text||'/'||:'patient'::text||'/photo.jpg'
 ),
 'row-level security'
);
select pg_temp.expect_error(
 format(
  $q$insert into storage.objects(bucket_id,name) values('clinical-attachments',%L)$q$,
  :'clinic'::text||'/'||:'case_id'::text||'/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.pdf'
 ),
 'row-level security'
);
reset role;

select pg_temp.assert_true(
 (select public=false and file_size_limit=8000000 from storage.buckets where id='patient-photos'),
 'patient photos bucket must remain private and capped'
);
select pg_temp.assert_true(
 (select public=false and file_size_limit=20000000 from storage.buckets where id='clinical-attachments'),
 'clinical attachments bucket must remain private and capped'
);
