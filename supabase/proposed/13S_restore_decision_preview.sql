-- Stage 2B.25: non-destructive restore decision simulation.
-- Produces a plan only. Existing rows are kept; nothing is overwritten or inserted.
begin;

alter table private.backup_restore_staging
 add column dependency_manifest_sha256 text,
 add column dependency_manifest jsonb,
 add column decision_plan jsonb,
 add column decision_report jsonb,
 add constraint backup_restore_dependency_hash_shape
  check(dependency_manifest_sha256 is null or dependency_manifest_sha256 ~ '^[a-f0-9]{64}$');

create function private.restore_dependency_target_allowed(p_table text)
returns boolean language sql immutable set search_path='' as $$
 select private.restore_conflict_table_allowed(p_table)
 or p_table in ('clinic_members','medication_product_versions');
$$;
revoke all on function private.restore_dependency_target_allowed(text) from public,anon,authenticated,service_role;

create function public.restore_preview_plan(
 p_clinic uuid,
 p_stage uuid,
 p_archive_sha256 text,
 p_conflict_manifest_sha256 text,
 p_dependency_manifest_sha256 text,
 p_dependencies jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 s private.backup_restore_staging;
 k text; row_id uuid; row_key text; deps jsonb; dep jsonb; dep_table text; dep_id uuid;
 incoming_ids uuid[]; supplied_ids uuid[]; target_status text;
 row_exists boolean; foreign_exists boolean; dep_exists boolean; blocked boolean; manual boolean; reason text;
 plan_index jsonb='{}'; details jsonb='{}'; tables_report jsonb='{}';
 create_n integer; keep_n integer; blocked_n integer; foreign_n integer; manual_n integer; table_total integer;
 total_create integer=0;total_keep integer=0;total_blocked integer=0;total_foreign integer=0;total_manual integer=0;
 samples_create jsonb;samples_keep jsonb;samples_blocked jsonb;samples_foreign jsonb;samples_manual jsonb;
 order_tables text[]=array[
  'vet_owners','inventario','form_templates','professional_profiles',
  'vet_patients','lotes_inventario','form_template_versions',
  'form_documents','hospital_stays','clinical_cases',
  'professional_delegations','prescriptions','medication_vials',
  'clinic_appointments','clinic_tasks','clinic_messages'
 ];
begin
 perform public.beta_access_check(false,p_clinic);
 if not private.restore_preview_authorized(p_clinic,auth.uid()) then raise exception 'backup_restore_required';end if;
 select * into s from private.backup_restore_staging
  where clinic_id=p_clinic and stage_id=p_stage and expires_at>clock_timestamp()
  for update;
 if not found then raise exception 'restore_stage_not_found';end if;
 if s.archive_sha256 is distinct from p_archive_sha256 then raise exception 'restore_archive_changed';end if;
 if s.conflict_manifest_sha256 is null or s.conflict_manifest is null or
    s.conflict_manifest_sha256 is distinct from p_conflict_manifest_sha256 then raise exception 'restore_conflicts_required';end if;
 if p_dependency_manifest_sha256 is null or p_dependency_manifest_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'restore_dependency_hash_required';end if;
 if p_dependencies is null or jsonb_typeof(p_dependencies)<>'object' then raise exception 'restore_dependencies_invalid';end if;

 -- No extra tables, and every stored incoming identifier must be represented exactly once.
 for k in select key from jsonb_each(p_dependencies) loop
  if not private.restore_conflict_table_allowed(k) or not (s.conflict_manifest ? k) then
   raise exception 'restore_dependencies_invalid';
  end if;
 end loop;
 for k in select key from jsonb_each(s.conflict_manifest) loop
  if not (p_dependencies ? k) or jsonb_typeof(p_dependencies->k)<>'object' then
   raise exception 'restore_dependencies_invalid';
  end if;
  select coalesce(array_agg((x#>>'{}')::uuid order by (x#>>'{}')::uuid),'{}'::uuid[])
    into incoming_ids from jsonb_array_elements(s.conflict_manifest->k) x;
  select coalesce(array_agg(key::uuid order by key::uuid),'{}'::uuid[])
    into supplied_ids from jsonb_each(p_dependencies->k);
  if incoming_ids<>supplied_ids then raise exception 'restore_dependencies_changed';end if;
 end loop;

 foreach k in array order_tables loop
  if not (s.conflict_manifest ? k) then continue;end if;
  create_n=0;keep_n=0;blocked_n=0;foreign_n=0;manual_n=0;table_total=0;
  samples_create='[]'::jsonb;samples_keep='[]'::jsonb;samples_blocked='[]'::jsonb;samples_foreign='[]'::jsonb;samples_manual='[]'::jsonb;

  for row_key,deps in select key,value from jsonb_each(p_dependencies->k) order by key loop
   table_total=table_total+1;
   begin row_id=row_key::uuid;exception when others then raise exception 'restore_dependencies_invalid';end;
   if jsonb_typeof(deps)<>'array' or jsonb_array_length(deps)>16 then raise exception 'restore_dependencies_invalid';end if;

   if k in ('form_templates','form_template_versions') then
    execute format('select exists(select 1 from public.%I where (clinic_id=$1 or clinic_id is null) and id=$2)',k)
     into row_exists using p_clinic,row_id;
    execute format('select exists(select 1 from public.%I where id=$1 and clinic_id is not null and clinic_id is distinct from $2)',k)
     into foreign_exists using row_id,p_clinic;
   else
    execute format('select exists(select 1 from public.%I where clinic_id=$1 and id=$2)',k)
     into row_exists using p_clinic,row_id;
    execute format('select exists(select 1 from public.%I where id=$1 and clinic_id is distinct from $2)',k)
     into foreign_exists using row_id,p_clinic;
   end if;

   if row_exists then
    target_status='keep_existing';reason='same_id_exists';
   elsif foreign_exists then
    target_status='blocked_foreign_identity';reason='same_id_other_workspace';
   else
    blocked=false;manual=false;reason='dependencies_satisfied';
    for dep in select value from jsonb_array_elements(deps) loop
     if jsonb_typeof(dep)<>'object' or dep->>'table' is null or dep->>'id' is null then raise exception 'restore_dependencies_invalid';end if;
     dep_table=dep->>'table';
     if not private.restore_dependency_target_allowed(dep_table) then raise exception 'restore_dependencies_invalid';end if;
     begin dep_id=(dep->>'id')::uuid;exception when others then raise exception 'restore_dependencies_invalid';end;

     if dep_table='clinic_members' then
      select exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=dep_id) into dep_exists;
      if not dep_exists then manual=true;reason='staff_reference_needs_review';end if;
     elsif dep_table='medication_product_versions' then
      select exists(select 1 from public.medication_product_versions where id=dep_id) into dep_exists;
      if not dep_exists then blocked=true;reason='missing_catalog_dependency';end if;
     elsif s.conflict_manifest ? dep_table and
           exists(select 1 from jsonb_array_elements_text(s.conflict_manifest->dep_table) as incoming(value) where incoming.value=dep_id::text) then
      target_status=plan_index->>(dep_table||':'||dep_id::text);
      if target_status is null then
       manual=true;reason='dependency_order_needs_review';
      elsif target_status in ('blocked_missing_dependency','blocked_foreign_identity','manual_review') then
       blocked=true;reason='incoming_parent_not_restorable';
      end if;
     else
      if dep_table in ('form_templates','form_template_versions') then
       execute format('select exists(select 1 from public.%I where (clinic_id=$1 or clinic_id is null) and id=$2)',dep_table)
        into dep_exists using p_clinic,dep_id;
      else
       execute format('select exists(select 1 from public.%I where clinic_id=$1 and id=$2)',dep_table)
        into dep_exists using p_clinic,dep_id;
      end if;
      if not dep_exists then blocked=true;reason='missing_parent';end if;
     end if;
    end loop;

    if blocked then target_status='blocked_missing_dependency';
    elsif manual then target_status='manual_review';
    else target_status='create_candidate';end if;
   end if;

   plan_index=plan_index||jsonb_build_object(k||':'||row_id::text,target_status);
   details=details||jsonb_build_object(k||':'||row_id::text,jsonb_build_object('status',target_status,'reason',reason));
   if target_status='create_candidate' then
    create_n=create_n+1;if jsonb_array_length(samples_create)<10 then samples_create=samples_create||to_jsonb(row_id::text);end if;
   elsif target_status='keep_existing' then
    keep_n=keep_n+1;if jsonb_array_length(samples_keep)<10 then samples_keep=samples_keep||to_jsonb(row_id::text);end if;
   elsif target_status='blocked_foreign_identity' then
    foreign_n=foreign_n+1;if jsonb_array_length(samples_foreign)<10 then samples_foreign=samples_foreign||to_jsonb(row_id::text);end if;
   elsif target_status='manual_review' then
    manual_n=manual_n+1;if jsonb_array_length(samples_manual)<10 then samples_manual=samples_manual||to_jsonb(row_id::text);end if;
   else
    blocked_n=blocked_n+1;if jsonb_array_length(samples_blocked)<10 then samples_blocked=samples_blocked||to_jsonb(row_id::text);end if;
   end if;
  end loop;

  total_create=total_create+create_n;total_keep=total_keep+keep_n;
  total_blocked=total_blocked+blocked_n;total_foreign=total_foreign+foreign_n;total_manual=total_manual+manual_n;
  tables_report=tables_report||jsonb_build_object(k,jsonb_build_object(
   'incoming',table_total,'create_candidate',create_n,'keep_existing',keep_n,
   'blocked_missing_dependency',blocked_n,'blocked_foreign_identity',foreign_n,'manual_review',manual_n,
   'samples',jsonb_build_object(
    'create_candidate',samples_create,'keep_existing',samples_keep,
    'blocked_missing_dependency',samples_blocked,'blocked_foreign_identity',samples_foreign,'manual_review',samples_manual
   )
  ));
 end loop;

 update private.backup_restore_staging
 set dependency_manifest_sha256=p_dependency_manifest_sha256,
     dependency_manifest=p_dependencies,
     decision_plan=details,
     decision_report=jsonb_build_object(
      'schema_version',1,'mode','restore_decision_preview',
      'archive_sha256',p_archive_sha256,
      'conflict_manifest_sha256',p_conflict_manifest_sha256,
      'dependency_manifest_sha256',p_dependency_manifest_sha256,
      'create_candidate',total_create,'keep_existing',total_keep,
      'blocked_missing_dependency',total_blocked,'blocked_foreign_identity',total_foreign,'manual_review',total_manual,
      'tables',tables_report,
      'policy',jsonb_build_object(
       'existing','keep_current','new','candidate_only',
       'missing_dependency','block','foreign_identity','block',
       'staff_reference','manual_review','overwrite',false,'merge',false
      ),
      'imports_applied',false,'planned_at',clock_timestamp()
     )
 where clinic_id=p_clinic and stage_id=p_stage
 returning decision_report into tables_report;

 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'backup_restore_decision_previewed',p_stage::text,
  jsonb_build_object('create_candidate',total_create,'keep_existing',total_keep,'blocked',total_blocked,'foreign_identity',total_foreign,'manual',total_manual));

 return tables_report;
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
   'conflicts',s.conflict_report,'decisions',s.decision_report
  ),
  'imports_applied',false
 );
end$$;

revoke all on function public.restore_preview_plan(uuid,uuid,text,text,text,jsonb) from public,anon;
grant execute on function public.restore_preview_plan(uuid,uuid,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
