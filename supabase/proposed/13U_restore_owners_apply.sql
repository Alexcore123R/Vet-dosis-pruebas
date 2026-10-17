-- Stage 2B.27: first real restore slice — vet_owners only.
-- The verified client payload is staged first. Apply is atomic, create-only and never overwrites.
begin;

alter table private.backup_restore_staging
 add column owner_payload_sha256 text,
 add column owner_payload jsonb,
 add column owner_payload_prepared_at timestamptz,
 add column owner_applied_at timestamptz,
 add column owner_apply_report jsonb,
 add constraint backup_restore_owner_payload_hash_shape
  check(owner_payload_sha256 is null or owner_payload_sha256 ~ '^[a-f0-9]{64}$');

-- Starting a fresh stage for the same clinic must clear all derived restore state,
-- including any prior owner application marker.
create or replace function public.restore_preview_stage(
 p_clinic uuid,
 p_format text,
 p_version integer,
 p_archive_sha256 text,
 p_source_server_at timestamptz,
 p_table_counts jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s private.backup_restore_staging;
begin
 perform public.beta_access_check(true,p_clinic);
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 if p_format is distinct from 'vetdosis-operational-backup' or p_version is distinct from 1 then raise exception 'restore_format_unsupported';end if;
 if p_archive_sha256 is null or p_archive_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'restore_hash_required';end if;
 if p_source_server_at is not null and p_source_server_at>clock_timestamp()+interval '5 minutes' then raise exception 'restore_source_time_invalid';end if;
 if not private.restore_counts_valid(p_table_counts) then raise exception 'restore_counts_invalid';end if;

 insert into private.backup_restore_staging(
  clinic_id,stage_id,requested_by,source_format,source_version,archive_sha256,
  source_server_at,table_counts,created_at,expires_at
 ) values(
  p_clinic,gen_random_uuid(),auth.uid(),p_format,p_version,p_archive_sha256,
  p_source_server_at,p_table_counts,clock_timestamp(),clock_timestamp()+interval '14 days'
 )
 on conflict(clinic_id) do update set
  stage_id=gen_random_uuid(),requested_by=excluded.requested_by,
  source_format=excluded.source_format,source_version=excluded.source_version,
  archive_sha256=excluded.archive_sha256,source_server_at=excluded.source_server_at,
  table_counts=excluded.table_counts,created_at=clock_timestamp(),
  expires_at=clock_timestamp()+interval '14 days',
  conflict_manifest_sha256=null,conflict_manifest=null,conflict_report=null,
  dependency_manifest_sha256=null,dependency_manifest=null,decision_plan=null,decision_report=null,
  preflight_id=null,preflight_report=null,preflight_checked_at=null,preflight_valid_until=null,
  owner_payload_sha256=null,owner_payload=null,owner_payload_prepared_at=null,
  owner_applied_at=null,owner_apply_report=null
 returning * into s;

 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'backup_restore_preview_staged',s.stage_id::text,
  jsonb_build_object('archive_sha256',s.archive_sha256,'expires_at',s.expires_at,'tables',(select count(*) from jsonb_object_keys(s.table_counts))));

 return jsonb_build_object(
  'schema_version',1,'mode','restore_preview',
  'stage_id',s.stage_id,'clinic_id',s.clinic_id,
  'archive_sha256',s.archive_sha256,'source_server_at',s.source_server_at,
  'table_counts',s.table_counts,'created_at',s.created_at,'expires_at',s.expires_at,
  'imports_applied',false
 );
end$$;

create function public.restore_prepare_owners(
 p_clinic uuid,
 p_stage uuid,
 p_archive_sha256 text,
 p_owners jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 s private.backup_restore_staging;
 row jsonb;row_id uuid;source_user uuid;source_at timestamptz;
 supplied uuid[];expected uuid[];payload_hash text;key text;
 create_n integer=0;keep_n integer=0;status text;
begin
 perform public.beta_access_check(true,p_clinic);
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 select * into s from private.backup_restore_staging
  where clinic_id=p_clinic and stage_id=p_stage and expires_at>clock_timestamp()
  for update;
 if not found then raise exception 'restore_stage_not_found';end if;
 if s.owner_applied_at is not null then raise exception 'restore_owner_already_applied';end if;
 if s.archive_sha256 is distinct from p_archive_sha256 then raise exception 'restore_archive_changed';end if;
 if s.conflict_manifest is null or s.decision_plan is null then raise exception 'restore_decision_preview_required';end if;
 if not (s.conflict_manifest ? 'vet_owners') then raise exception 'restore_owner_scope_absent';end if;
 if p_owners is null or jsonb_typeof(p_owners)<>'array' or jsonb_array_length(p_owners) not between 1 and 5000 then
  raise exception 'restore_owner_payload_invalid';
 end if;
 if octet_length(p_owners::text)>8000000 then raise exception 'restore_owner_payload_too_large';end if;

 select coalesce(array_agg((x->>'id')::uuid order by (x->>'id')::uuid),'{}'::uuid[])
 into supplied from jsonb_array_elements(p_owners) x;
 select coalesce(array_agg((x#>>'{}')::uuid order by (x#>>'{}')::uuid),'{}'::uuid[])
 into expected from jsonb_array_elements(s.conflict_manifest->'vet_owners') x;
 if supplied<>expected then raise exception 'restore_owner_payload_changed';end if;
 if cardinality(supplied)<>jsonb_array_length(p_owners) then raise exception 'restore_owner_payload_duplicate';end if;

 for row in select value from jsonb_array_elements(p_owners) loop
  if jsonb_typeof(row)<>'object' then raise exception 'restore_owner_payload_invalid';end if;
  for key in select jsonb_object_keys(row) loop
   if key not in ('id','clinic_id','name','phone','email','address','source_created_by','source_created_at') then
    raise exception 'restore_owner_payload_invalid';
   end if;
  end loop;
  begin row_id=(row->>'id')::uuid;exception when others then raise exception 'restore_owner_payload_invalid';end;
  if row->>'clinic_id' is distinct from p_clinic::text then raise exception 'restore_owner_wrong_clinic';end if;
  if jsonb_typeof(row->'name')<>'string' or length(btrim(row->>'name')) not between 1 and 200 then raise exception 'restore_owner_payload_invalid';end if;
  foreach key in array array['phone','email','address'] loop
   if row->key is not null and jsonb_typeof(row->key)<>'string' then raise exception 'restore_owner_payload_invalid';end if;
   if length(coalesce(row->>key,''))>1000 then raise exception 'restore_owner_payload_invalid';end if;
  end loop;
  if row->>'source_created_by' is not null then
   begin source_user=(row->>'source_created_by')::uuid;exception when others then raise exception 'restore_owner_payload_invalid';end;
  else source_user=null;end if;
  if row->>'source_created_at' is not null then
   begin source_at=(row->>'source_created_at')::timestamptz;exception when others then raise exception 'restore_owner_payload_invalid';end;
   if source_at>clock_timestamp()+interval '5 minutes' then raise exception 'restore_owner_payload_invalid';end if;
  else source_at=null;end if;

  status=s.decision_plan->('vet_owners:'||row_id::text)->>'status';
  if status='create_candidate' then create_n=create_n+1;
  elsif status='keep_existing' then keep_n=keep_n+1;
  else raise exception 'restore_owner_decision_not_applicable';end if;
 end loop;

 payload_hash=encode(extensions.digest(convert_to(p_owners::text,'UTF8'),'sha256'),'hex');
 update private.backup_restore_staging
 set owner_payload_sha256=payload_hash,
     owner_payload=p_owners,
     owner_payload_prepared_at=clock_timestamp(),
     owner_applied_at=null,
     owner_apply_report=null,
     preflight_id=null,
     preflight_report=null,
     preflight_checked_at=null,
     preflight_valid_until=null
 where clinic_id=p_clinic and stage_id=p_stage;

 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'backup_restore_owners_prepared',p_stage::text,
  jsonb_build_object('archive_sha256',p_archive_sha256,'payload_sha256',payload_hash,'create_candidate',create_n,'keep_existing',keep_n));

 return jsonb_build_object(
  'schema_version',1,'mode','restore_owner_payload',
  'stage_id',p_stage,'archive_sha256',p_archive_sha256,
  'payload_sha256',payload_hash,'rows',jsonb_array_length(p_owners),
  'create_candidate',create_n,'keep_existing',keep_n,
  'prepared_at',clock_timestamp(),'imports_applied',false
 );
end$$;

create function public.restore_apply_owners(
 p_clinic uuid,
 p_stage uuid,
 p_preflight uuid,
 p_owner_payload_sha256 text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 s private.backup_restore_staging;
 row jsonb;row_id uuid;status text;source_user uuid;source_at timestamptz;
 created_n integer=0;kept_n integer=0;report jsonb;
begin
 perform public.beta_access_check(true,p_clinic);
 perform 1 from public.clinics where id=p_clinic for update;
 if not found then raise exception 'restore_clinic_not_found';end if;
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 if not private.restore_apply_test_target(p_clinic) then raise exception 'restore_test_target_required';end if;

 select * into s from private.backup_restore_staging
  where clinic_id=p_clinic and stage_id=p_stage and expires_at>clock_timestamp()
  for update;
 if not found then raise exception 'restore_stage_not_found';end if;

 if s.owner_applied_at is not null then
  if s.owner_payload_sha256=p_owner_payload_sha256 then return s.owner_apply_report;end if;
  raise exception 'restore_owner_already_applied';
 end if;
 if s.owner_payload is null or s.owner_payload_sha256 is null or s.owner_payload_sha256 is distinct from p_owner_payload_sha256 then
  raise exception 'restore_owner_payload_changed';
 end if;
 if s.preflight_id is null or s.preflight_id is distinct from p_preflight or s.preflight_report is null then
  raise exception 'restore_preflight_required';
 end if;
 if coalesce((s.preflight_report->>'applicable')::boolean,false) is not true then raise exception 'restore_preflight_blocked';end if;
 if s.preflight_valid_until is null or s.preflight_valid_until<=clock_timestamp() then raise exception 'restore_preflight_expired';end if;
 if s.preflight_report->>'archive_sha256'<>s.archive_sha256 or
    s.preflight_report->>'conflict_manifest_sha256'<>s.conflict_manifest_sha256 or
    s.preflight_report->>'dependency_manifest_sha256'<>s.dependency_manifest_sha256 then
  raise exception 'restore_preflight_changed';
 end if;

 -- Re-check the complete owner slice inside the same transaction used by the inserts.
 for row in select value from jsonb_array_elements(s.owner_payload) loop
  row_id=(row->>'id')::uuid;
  status=s.decision_plan->('vet_owners:'||row_id::text)->>'status';
  if status='keep_existing' then
   if not exists(select 1 from public.vet_owners where clinic_id=p_clinic and id=row_id) then
    raise exception 'restore_owner_state_drift';
   end if;
   kept_n=kept_n+1;
  elsif status='create_candidate' then
   if exists(select 1 from public.vet_owners where id=row_id) then raise exception 'restore_owner_state_drift';end if;
  else
   raise exception 'restore_owner_decision_not_applicable';
  end if;
 end loop;

 for row in select value from jsonb_array_elements(s.owner_payload) order by value->>'id' loop
  row_id=(row->>'id')::uuid;
  status=s.decision_plan->('vet_owners:'||row_id::text)->>'status';
  if status<>'create_candidate' then continue;end if;
  source_user=nullif(row->>'source_created_by','')::uuid;
  source_at=nullif(row->>'source_created_at','')::timestamptz;
  insert into public.vet_owners(id,clinic_id,name,phone,email,address,created_by,created_at)
  values(
   row_id,p_clinic,btrim(row->>'name'),coalesce(row->>'phone',''),coalesce(row->>'email',''),coalesce(row->>'address',''),
   auth.uid(),coalesce(source_at,clock_timestamp())
  );
  created_n=created_n+1;
  insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
  values(p_clinic,auth.uid(),'owner_restored_from_backup',row_id::text,
   jsonb_build_object(
    'stage_id',p_stage,'archive_sha256',s.archive_sha256,'payload_sha256',s.owner_payload_sha256,
    'source_created_by',source_user,'source_created_at',source_at
   ));
 end loop;

 report=jsonb_build_object(
  'schema_version',1,'mode','restore_apply_owners',
  'stage_id',p_stage,'preflight_id',p_preflight,
  'archive_sha256',s.archive_sha256,'payload_sha256',s.owner_payload_sha256,
  'created',created_n,'kept_existing',kept_n,
  'scope','vet_owners','overwrite',false,'merge',false,
  'applied_at',clock_timestamp(),'imports_applied',true
 );

 update private.backup_restore_staging
 set owner_applied_at=(report->>'applied_at')::timestamptz,
     owner_apply_report=report,
     preflight_valid_until=clock_timestamp()
 where clinic_id=p_clinic and stage_id=p_stage;

 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'backup_restore_owners_applied',p_stage::text,
  jsonb_build_object('preflight_id',p_preflight,'created',created_n,'kept_existing',kept_n,'payload_sha256',s.owner_payload_sha256));

 return report;
end$$;

create or replace function public.restore_preview_get(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s private.backup_restore_staging;
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 select * into s from private.backup_restore_staging where clinic_id=p_clinic and expires_at>clock_timestamp();
 if not found then return jsonb_build_object('schema_version',1,'mode','restore_preview','stage',null,'imports_applied',false);end if;
 return jsonb_build_object(
  'schema_version',1,'mode','restore_preview','stage',
  jsonb_build_object(
   'stage_id',s.stage_id,'archive_sha256',s.archive_sha256,'source_server_at',s.source_server_at,
   'table_counts',s.table_counts,'created_at',s.created_at,'expires_at',s.expires_at,
   'conflicts',s.conflict_report,'decisions',s.decision_report,'preflight',s.preflight_report,
   'owner_payload',case when s.owner_payload is null then null else jsonb_build_object(
    'payload_sha256',s.owner_payload_sha256,'rows',jsonb_array_length(s.owner_payload),
    'prepared_at',s.owner_payload_prepared_at,'applied_at',s.owner_applied_at,'apply_report',s.owner_apply_report
   ) end
  ),
  'imports_applied',s.owner_applied_at is not null
 );
end$$;

revoke all on function public.restore_prepare_owners(uuid,uuid,text,jsonb),public.restore_apply_owners(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.restore_prepare_owners(uuid,uuid,text,jsonb),public.restore_apply_owners(uuid,uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';
commit;
