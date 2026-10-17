-- Stage 2B.23: restore preview staging only.
-- Stores metadata/counts for one clinic backup preview. It NEVER imports backup rows.
begin;

create table private.backup_restore_staging(
 clinic_id uuid primary key references public.clinics(id) on delete cascade,
 stage_id uuid not null unique default gen_random_uuid(),
 requested_by uuid not null references auth.users(id),
 source_format text not null,
 source_version integer not null,
 archive_sha256 text not null check(archive_sha256 ~ '^[a-f0-9]{64}$'),
 source_server_at timestamptz,
 table_counts jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null,
 check(expires_at>created_at)
);
alter table private.backup_restore_staging enable row level security;
revoke all on private.backup_restore_staging from public,anon,authenticated,service_role;

create function private.restore_preview_authorized(p_clinic uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null
 and exists(select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=p_user)
 and exists(select 1 from public.account_workspaces w where w.clinic_id=p_clinic and w.kind='clinic')
 and private.permission_effective(p_clinic,p_user,'backup.restore') is not null
 and (
  private.permission_effective(p_clinic,p_user,'workspace.manage') is not null
  or (p_user=auth.uid() and private.permission_responsible(p_clinic))
 );
$$;
revoke all on function private.restore_preview_authorized(uuid,uuid) from public,anon,authenticated,service_role;

create function private.restore_counts_valid(p_counts jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare k text;v jsonb;n bigint;keys_count integer;
begin
 if p_counts is null or jsonb_typeof(p_counts)<>'object' then return false;end if;
 select count(*)::integer into keys_count from jsonb_object_keys(p_counts);
 if keys_count<1 or keys_count>100 then return false;end if;
 for k,v in select key,value from jsonb_each(p_counts) loop
  if k !~ '^[a-zA-Z0-9_]{1,100}$' or jsonb_typeof(v)<>'number' then return false;end if;
  begin n=(v#>>'{}')::bigint;exception when others then return false;end;
  if n<0 or n>10000000 then return false;end if;
 end loop;
 return true;
end$$;
revoke all on function private.restore_counts_valid(jsonb) from public,anon,authenticated,service_role;

create or replace function public.backup_workspace(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare kind text;
begin
 perform public.beta_access_check(false,p_clinic);
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'current_member_required';end if;
 select workspace_kind.kind into kind from public.account_workspaces workspace_kind where clinic_id=p_clinic;
 return jsonb_build_object(
  'schema_version',1,'mode','explicit_backup','workspace_kind',kind,
  'exports',jsonb_build_object('clinic',private.backup_clinic_authorized(p_clinic),'personal',private.backup_personal_authorized(p_clinic)),
  'statistics',private.permission_effective(p_clinic,auth.uid(),'sales.read') is not null,
  'restore_preview',private.restore_preview_authorized(p_clinic,auth.uid())
 );
end$$;

create function public.restore_preview_stage(
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
 if p_format<>'vetdosis-operational-backup' or p_version<>1 then raise exception 'restore_format_unsupported';end if;
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
  expires_at=clock_timestamp()+interval '14 days'
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

create function public.restore_preview_get(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s private.backup_restore_staging;
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 select * into s from private.backup_restore_staging where clinic_id=p_clinic and expires_at>clock_timestamp();
 if not found then return jsonb_build_object('schema_version',1,'mode','restore_preview','stage',null,'imports_applied',false);end if;
 return jsonb_build_object(
  'schema_version',1,'mode','restore_preview','stage',
  jsonb_build_object('stage_id',s.stage_id,'archive_sha256',s.archive_sha256,'source_server_at',s.source_server_at,'table_counts',s.table_counts,'created_at',s.created_at,'expires_at',s.expires_at),
  'imports_applied',false
 );
end$$;

create function public.restore_preview_discard(p_clinic uuid,p_stage uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.beta_access_check(true,p_clinic);
 perform 1 from public.clinics where id=p_clinic for update;
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 delete from private.backup_restore_staging where clinic_id=p_clinic and stage_id=p_stage;
 if not found then raise exception 'restore_stage_not_found';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id)
 values(p_clinic,auth.uid(),'backup_restore_preview_discarded',p_stage::text);
end$$;

revoke all on function public.backup_workspace(uuid),public.restore_preview_stage(uuid,text,integer,text,timestamptz,jsonb),public.restore_preview_get(uuid),public.restore_preview_discard(uuid,uuid) from public,anon;
grant execute on function public.backup_workspace(uuid),public.restore_preview_stage(uuid,text,integer,text,timestamptz,jsonb),public.restore_preview_get(uuid),public.restore_preview_discard(uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
