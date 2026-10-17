-- Stage 2B.26: restore application preflight.
-- Final safety check only. It never imports, updates, merges or deletes operational rows.
begin;

alter table private.backup_restore_staging
 add column preflight_id uuid,
 add column preflight_report jsonb,
 add column preflight_checked_at timestamptz,
 add column preflight_valid_until timestamptz;

create function public.restore_preview_preflight(
 p_clinic uuid,
 p_stage uuid,
 p_archive_sha256 text,
 p_conflict_manifest_sha256 text,
 p_dependency_manifest_sha256 text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 s private.backup_restore_staging;
 plan_key text; decision jsonb; status text; parts text[]; row_table text; row_id uuid;
 deps jsonb; dep jsonb; dep_table text; dep_id uuid; dep_status text;
 row_exists boolean; foreign_exists boolean; dep_exists boolean;
 blockers jsonb='[]'::jsonb; checked integer=0;
 v_preflight uuid=gen_random_uuid(); report jsonb;
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;

 select * into s from private.backup_restore_staging
  where clinic_id=p_clinic and stage_id=p_stage and expires_at>clock_timestamp()
  for update;
 if not found then raise exception 'restore_stage_not_found';end if;
 if s.archive_sha256 is distinct from p_archive_sha256 then raise exception 'restore_archive_changed';end if;
 if s.conflict_manifest_sha256 is null or s.conflict_manifest is null or
    s.conflict_manifest_sha256 is distinct from p_conflict_manifest_sha256 then raise exception 'restore_conflicts_changed';end if;
 if s.dependency_manifest_sha256 is null or s.dependency_manifest is null or
    s.dependency_manifest_sha256 is distinct from p_dependency_manifest_sha256 then raise exception 'restore_dependencies_changed';end if;
 if s.decision_plan is null or s.decision_report is null then raise exception 'restore_decision_preview_required';end if;
 if s.decision_report->>'archive_sha256' is distinct from p_archive_sha256 or
    s.decision_report->>'conflict_manifest_sha256' is distinct from p_conflict_manifest_sha256 or
    s.decision_report->>'dependency_manifest_sha256' is distinct from p_dependency_manifest_sha256 then
   raise exception 'restore_decision_preview_changed';
 end if;

 if coalesce((s.decision_report->>'blocked_missing_dependency')::int,0)>0 then
  blockers=blockers||jsonb_build_object('code','blocked_missing_dependency','count',(s.decision_report->>'blocked_missing_dependency')::int);
 end if;
 if coalesce((s.decision_report->>'blocked_foreign_identity')::int,0)>0 then
  blockers=blockers||jsonb_build_object('code','blocked_foreign_identity','count',(s.decision_report->>'blocked_foreign_identity')::int);
 end if;
 if coalesce((s.decision_report->>'manual_review')::int,0)>0 then
  blockers=blockers||jsonb_build_object('code','manual_review','count',(s.decision_report->>'manual_review')::int);
 end if;
 if coalesce((s.decision_report->'policy'->>'overwrite')::boolean,true) or
    coalesce((s.decision_report->'policy'->>'merge')::boolean,true) then
  blockers=blockers||jsonb_build_object('code','unsafe_policy');
 end if;

 -- Re-check every planned row against current state to detect drift after simulation.
 for plan_key,decision in select key,value from jsonb_each(s.decision_plan) order by key loop
  checked=checked+1;
  status=decision->>'status';
  if status is null or status not in ('keep_existing','create_candidate','blocked_missing_dependency','blocked_foreign_identity','manual_review') then
   blockers=blockers||jsonb_build_object('code','invalid_plan_status','entry',plan_key);
   continue;
  end if;
  parts=string_to_array(plan_key,':');
  if cardinality(parts)<>2 or not private.restore_conflict_table_allowed(parts[1]) then
   blockers=blockers||jsonb_build_object('code','invalid_plan_entry','entry',plan_key);
   continue;
  end if;
  row_table=parts[1];
  begin row_id=parts[2]::uuid;exception when others then
   blockers=blockers||jsonb_build_object('code','invalid_plan_entry','entry',plan_key);
   continue;
  end;

  execute format('select exists(select 1 from public.%I where clinic_id=$1 and id=$2)',row_table)
   into row_exists using p_clinic,row_id;
  execute format('select exists(select 1 from public.%I where id=$1 and clinic_id is distinct from $2)',row_table)
   into foreign_exists using row_id,p_clinic;

  if status='keep_existing' then
   if not row_exists then blockers=blockers||jsonb_build_object('code','state_drift_existing_missing','table',row_table,'id',row_id);end if;
   continue;
  end if;
  if status<>'create_candidate' then continue;end if;

  if row_exists then
   blockers=blockers||jsonb_build_object('code','state_drift_now_exists','table',row_table,'id',row_id);
   continue;
  end if;
  if foreign_exists then
   blockers=blockers||jsonb_build_object('code','state_drift_foreign_identity','table',row_table,'id',row_id);
   continue;
  end if;

  deps=s.dependency_manifest->row_table->(row_id::text);
  if deps is null or jsonb_typeof(deps)<>'array' then
   blockers=blockers||jsonb_build_object('code','dependency_manifest_missing','table',row_table,'id',row_id);
   continue;
  end if;

  for dep in select value from jsonb_array_elements(deps) loop
   dep_table=dep->>'table';
   begin dep_id=(dep->>'id')::uuid;exception when others then
    blockers=blockers||jsonb_build_object('code','dependency_manifest_invalid','table',row_table,'id',row_id);
    continue;
   end;

   if dep_table='clinic_members' then
    select exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=dep_id) into dep_exists;
    if not dep_exists then blockers=blockers||jsonb_build_object('code','staff_reference_changed','table',row_table,'id',row_id,'dependency',dep_id);end if;
   elsif dep_table='medication_product_versions' then
    select exists(select 1 from public.medication_product_versions where id=dep_id) into dep_exists;
    if not dep_exists then blockers=blockers||jsonb_build_object('code','catalog_dependency_changed','table',row_table,'id',row_id,'dependency',dep_id);end if;
   elsif s.conflict_manifest ? dep_table and
         exists(select 1 from jsonb_array_elements_text(s.conflict_manifest->dep_table) incoming(value) where incoming.value=dep_id::text) then
    dep_status=s.decision_plan->(dep_table||':'||dep_id::text)->>'status';
    if dep_status is null or dep_status not in ('create_candidate','keep_existing') then
     blockers=blockers||jsonb_build_object('code','incoming_dependency_not_applicable','table',row_table,'id',row_id,'dependency_table',dep_table,'dependency',dep_id);
    end if;
   else
    if dep_table in ('form_templates','form_template_versions') then
     execute format('select exists(select 1 from public.%I where (clinic_id=$1 or clinic_id is null) and id=$2)',dep_table)
      into dep_exists using p_clinic,dep_id;
    else
     execute format('select exists(select 1 from public.%I where clinic_id=$1 and id=$2)',dep_table)
      into dep_exists using p_clinic,dep_id;
    end if;
    if not dep_exists then blockers=blockers||jsonb_build_object('code','dependency_state_changed','table',row_table,'id',row_id,'dependency_table',dep_table,'dependency',dep_id);end if;
   end if;
  end loop;
 end loop;

 report=jsonb_build_object(
  'schema_version',1,'mode','restore_preflight',
  'preflight_id',v_preflight,'stage_id',p_stage,
  'archive_sha256',p_archive_sha256,
  'conflict_manifest_sha256',p_conflict_manifest_sha256,
  'dependency_manifest_sha256',p_dependency_manifest_sha256,
  'checked_entries',checked,
  'applicable',jsonb_array_length(blockers)=0,
  'blockers',blockers,
  'checked_at',clock_timestamp(),
  'valid_until',clock_timestamp()+interval '15 minutes',
  'imports_applied',false
 );

 update private.backup_restore_staging
 set preflight_id=v_preflight,
     preflight_report=report,
     preflight_checked_at=(report->>'checked_at')::timestamptz,
     preflight_valid_until=(report->>'valid_until')::timestamptz
 where clinic_id=p_clinic and stage_id=p_stage;

 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'backup_restore_preflight_checked',v_preflight::text,
  jsonb_build_object('stage_id',p_stage,'applicable',report->'applicable','blockers',jsonb_array_length(blockers),'checked_entries',checked));

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
   'conflicts',s.conflict_report,'decisions',s.decision_report,'preflight',s.preflight_report
  ),
  'imports_applied',false
 );
end$$;

revoke all on function public.restore_preview_preflight(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.restore_preview_preflight(uuid,uuid,text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
