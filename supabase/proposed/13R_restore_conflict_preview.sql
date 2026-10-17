-- Stage 2B.24: non-destructive restore conflict preview.
-- Accepts only identifiers from an already verified/staged archive. Never imports rows.
begin;

alter table private.backup_restore_staging
 add column conflict_manifest_sha256 text,
 add column conflict_manifest jsonb,
 add column conflict_report jsonb,
 add constraint backup_restore_conflict_hash_shape
  check(conflict_manifest_sha256 is null or conflict_manifest_sha256 ~ '^[a-f0-9]{64}$');

create function private.restore_conflict_table_allowed(p_table text)
returns boolean language sql immutable set search_path='' as $$
 select p_table=any(array[
  'vet_owners','vet_patients','clinical_cases','hospital_stays',
  'form_templates','form_template_versions','form_documents',
  'professional_profiles','professional_delegations',
  'prescriptions','medication_vials','inventario','lotes_inventario',
  'clinic_appointments','clinic_tasks','clinic_messages'
 ]::text[]);
$$;
revoke all on function private.restore_conflict_table_allowed(text) from public,anon,authenticated,service_role;

create function private.restore_manifest_valid(p_manifest jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare k text;v jsonb;x jsonb;n integer=0;
begin
 if p_manifest is null or jsonb_typeof(p_manifest)<>'object' then return false;end if;
 if (select count(*) from jsonb_object_keys(p_manifest))<1 or (select count(*) from jsonb_object_keys(p_manifest))>32 then return false;end if;
 for k,v in select key,value from jsonb_each(p_manifest) loop
  if not private.restore_conflict_table_allowed(k) or jsonb_typeof(v)<>'array' then return false;end if;
  if jsonb_array_length(v)>10000 then return false;end if;
  for x in select value from jsonb_array_elements(v) loop
   if jsonb_typeof(x)<>'string' or (x#>>'{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false;end if;
   n=n+1;if n>25000 then return false;end if;
  end loop;
 end loop;
 return true;
end$$;
revoke all on function private.restore_manifest_valid(jsonb) from public,anon,authenticated,service_role;

create function public.restore_preview_conflicts(
 p_clinic uuid,
 p_stage uuid,
 p_archive_sha256 text,
 p_manifest_sha256 text,
 p_manifest jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s private.backup_restore_staging;k text;v jsonb;ids uuid[];existing uuid[];foreign_ids uuid[];incoming integer;report jsonb='{}';total_incoming integer=0;total_existing integer=0;total_foreign integer=0;
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 select * into s from private.backup_restore_staging
  where clinic_id=p_clinic and stage_id=p_stage and expires_at>clock_timestamp()
  for update;
 if not found then raise exception 'restore_stage_not_found';end if;
 if s.archive_sha256<>p_archive_sha256 then raise exception 'restore_archive_changed';end if;
 if p_manifest_sha256 is null or p_manifest_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'restore_manifest_hash_required';end if;
 if not private.restore_manifest_valid(p_manifest) then raise exception 'restore_manifest_invalid';end if;

 for k,v in select key,value from jsonb_each(p_manifest) order by key loop
  select coalesce(array_agg(distinct (x#>>'{}')::uuid),'{}'::uuid[]) into ids
   from jsonb_array_elements(v) x;
  incoming=coalesce(cardinality(ids),0);
  execute format(
   'select coalesce(array_agg(id order by id),''{}''::uuid[]) from public.%I where clinic_id=$1 and id=any($2)',
   k
  ) into existing using p_clinic,ids;
  execute format(
   'select coalesce(array_agg(id order by id),''{}''::uuid[]) from public.%I where id=any($1) and clinic_id is distinct from $2',
   k
  ) into foreign_ids using ids,p_clinic;
  total_incoming=total_incoming+incoming;
  total_existing=total_existing+coalesce(cardinality(existing),0);
  total_foreign=total_foreign+coalesce(cardinality(foreign_ids),0);
  report=report||jsonb_build_object(k,jsonb_build_object(
   'incoming',incoming,
   'existing',coalesce(cardinality(existing),0),
   'foreign_conflict',coalesce(cardinality(foreign_ids),0),
   'new',incoming-coalesce(cardinality(existing),0)-coalesce(cardinality(foreign_ids),0),
   'conflict_ids',to_jsonb(coalesce(existing[1:100],'{}'::uuid[])),
   'foreign_conflict_ids',to_jsonb(coalesce(foreign_ids[1:100],'{}'::uuid[])),
   'conflicts_truncated',coalesce(cardinality(existing),0)>100,
   'foreign_conflicts_truncated',coalesce(cardinality(foreign_ids),0)>100
  ));
 end loop;

 update private.backup_restore_staging
 set conflict_manifest_sha256=p_manifest_sha256,
     conflict_manifest=p_manifest,
     conflict_report=jsonb_build_object(
      'schema_version',1,'mode','restore_conflicts',
      'archive_sha256',p_archive_sha256,
      'manifest_sha256',p_manifest_sha256,
      'incoming',total_incoming,'existing',total_existing,'foreign_conflict',total_foreign,
      'new',total_incoming-total_existing-total_foreign,
      'tables',report,'imports_applied',false,'checked_at',clock_timestamp()
     )
 where clinic_id=p_clinic and stage_id=p_stage
 returning conflict_report into report;

 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'backup_restore_conflicts_previewed',p_stage::text,
  jsonb_build_object('archive_sha256',p_archive_sha256,'manifest_sha256',p_manifest_sha256,'incoming',total_incoming,'existing',total_existing,'foreign_conflict',total_foreign));

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
   'conflicts',s.conflict_report
  ),
  'imports_applied',false
 );
end$$;

revoke all on function public.restore_preview_conflicts(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.restore_preview_conflicts(uuid,uuid,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
