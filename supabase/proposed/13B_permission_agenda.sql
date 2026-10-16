-- 2B-2 LOCAL CANDIDATE. Apply only as part of the coordinated authorization cutover.
-- Keeps plan checks; no grants, clinical habilitations, beta flags or data are seeded.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
 if to_regprocedure('public.ops_write_before_plans(uuid,text,jsonb,text)') is null then raise exception 'plan_wrapper_required';end if;
end$$;
create function private.permission_appointment_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare grant_id uuid;patient_grant uuid;v_id uuid;v_appointment public.clinic_appointments;v_prof uuid;v_start timestamptz;v_end timestamptz;fp jsonb;v_patient public.vet_patients;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 perform 1 from public.clinics where id=p_clinic for update;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 grant_id=private.permission_require(p_clinic,'appointment.manage');
 if not exists(select 1 from private.member_permission_grants where id=grant_id and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 if p_action is null or p_action not in ('appointment','appointment_state','appointment_reschedule') then raise exception 'unknown_operation';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
 -- Check both permissions before returning an idempotent response.
 if p_action='appointment' and nullif(p_data->>'patient_id','') is not null then
  patient_grant=private.permission_require(p_clinic,'patient.read');
  if not exists(select 1 from private.member_permission_grants where id=patient_grant and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 end if;
 fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);
 v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_action='appointment' then
 v_prof=(p_data->>'professional_id')::uuid;v_start=(p_data->>'starts_at')::timestamptz;v_end=(p_data->>'ends_at')::timestamptz;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_prof for update;
 if not found then raise exception 'invalid_professional';end if;
 if exists(select 1 from public.clinic_appointments where clinic_id=p_clinic and professional_id=v_prof and state not in ('cancelado','entregado') and starts_at<v_end and ends_at>v_start) then raise exception 'appointment_overlap';end if;
 if nullif(p_data->>'patient_id','') is not null then
 select * into v_patient from public.vet_patients where clinic_id=p_clinic and id=(p_data->>'patient_id')::uuid for share;
 if not found then raise exception 'patient_wrong_clinic';end if;
 end if;
 insert into public.clinic_appointments(clinic_id,patient_id,patient_name,species,kind,professional_id,starts_at,ends_at,notes,created_by)
 values(p_clinic,v_patient.id,coalesce(v_patient.name,p_data->>'patient_name'),coalesce(v_patient.species,p_data->>'species'),p_data->>'kind',v_prof,v_start,v_end,coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 if v_patient.id is null and (coalesce(length(btrim(p_data->>'patient_name')),0) not between 1 and 150 or coalesce(length(btrim(p_data->>'species')),0) not between 1 and 120) then raise exception 'patient_required';end if;
 elsif p_action='appointment_state' then
 v_id=(p_data->>'id')::uuid;
 select * into v_appointment from public.clinic_appointments where id=v_id and clinic_id=p_clinic for update;
 if not found then raise exception 'access_denied';end if;
 if v_appointment.version is distinct from (p_data->>'version')::int then raise exception 'version_conflict';end if;
 if v_appointment.state in ('cancelado','entregado') then raise exception 'appointment_closed';end if;
 if not ((v_appointment.state='agendado' and p_data->>'state' in ('en_atencion','cancelado')) or (v_appointment.state='en_atencion' and p_data->>'state' in ('listo','cancelado')) or (v_appointment.state='listo' and p_data->>'state'='entregado')) then raise exception 'invalid_transition';end if;
 if p_data->>'state'='cancelado' and coalesce(length(btrim(p_data->>'reason')),0) not between 3 and 1000 then raise exception 'appointment_reason_required';end if;
 update public.clinic_appointments set state=p_data->>'state',version=version+1 where id=v_id;
 if p_data->>'state'='cancelado' then
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'appointment_cancelled',v_id::text,jsonb_build_object('reason',btrim(p_data->>'reason'),'previous_state',v_appointment.state,'previous_version',v_appointment.version));
 end if;
 elsif p_action='appointment_reschedule' then
 v_id=(p_data->>'id')::uuid;
 select * into v_appointment from public.clinic_appointments where clinic_id=p_clinic and id=v_id for update;
 if not found then raise exception 'access_denied';end if;
 if v_appointment.version is distinct from (p_data->>'version')::int then raise exception 'version_conflict';end if;
 if v_appointment.state<>'agendado' then raise exception 'appointment_not_scheduled';end if;
 if coalesce(length(btrim(p_data->>'reason')),0) not between 3 and 1000 then raise exception 'appointment_reason_required';end if;
 v_start=(p_data->>'starts_at')::timestamptz; v_end=(p_data->>'ends_at')::timestamptz;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_appointment.professional_id for update;
 if not found then raise exception 'invalid_professional';end if;
 if exists(select 1 from public.clinic_appointments where clinic_id=p_clinic and id<>v_id and professional_id=v_appointment.professional_id and state not in ('cancelado','entregado') and starts_at<v_end and ends_at>v_start) then raise exception 'appointment_overlap';end if;
 update public.clinic_appointments set starts_at=v_start,ends_at=v_end,version=version+1 where id=v_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'appointment_rescheduled',v_id::text,jsonb_build_object('reason',btrim(p_data->>'reason'),'previous_start',v_appointment.starts_at,'previous_end',v_appointment.ends_at,'starts_at',v_start,'ends_at',v_end,'previous_version',v_appointment.version));
 else raise exception 'unknown_operation';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'ops_'||p_action,v_id::text,jsonb_build_object('permission_grant_id',grant_id,'patient_read_grant_id',patient_grant));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
revoke all on function private.permission_appointment_write(uuid,text,jsonb,text) from public,anon,authenticated;
-- Preserve the outer plan guard and the existing non-agenda operations; no legacy
-- appointment path is reachable by an authenticated caller of either public RPC.
revoke all on function public.ops_write_before_plans(uuid,text,jsonb,text) from public,anon,authenticated;
create or replace function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 if p_action in ('appointment','appointment_state','appointment_reschedule') then return private.permission_appointment_write(p_clinic,p_action,p_data,p_operation);end if;
 if p_action in ('task','task_complete','message') and not private.team_plan(p_clinic) then raise exception 'clinic_plan_required';end if;
 return public.ops_write_before_plans(p_clinic,p_action,p_data,p_operation);
end$$;
create or replace function public.ops_patient_search(p_clinic uuid,p_query text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.permission_require(p_clinic,'patient.read');
 if p_query is null or char_length(btrim(p_query)) not between 1 and 120 then raise exception 'patient_search_required';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'species',species) order by name,id),'[]') from
 (select id,name,species from public.vet_patients where clinic_id=p_clinic and strpos(lower(name),lower(btrim(p_query)))>0 order by name,id limit 50) p);
end$$;
create or replace function public.ops_dashboard(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare can_read boolean;can_manage boolean;can_patient boolean;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 can_read=private.permission_effective(p_clinic,auth.uid(),'appointment.read') is not null;
 can_manage=private.permission_effective(p_clinic,auth.uid(),'appointment.manage') is not null;
 can_patient=private.permission_effective(p_clinic,auth.uid(),'patient.read') is not null;
 return jsonb_build_object(
 'permissions',jsonb_build_object('appointment.read',can_read,'appointment.manage',can_manage,'patient.read',can_patient),
 'sections',jsonb_build_object('appointments',can_read or can_manage,'services',false,'tasks',false,'messages',false,'suppliers',false,'acts',false),
 'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'role','member','display_name',n.name)),'[]') from public.clinic_members m left join public.staff_display_names n using(clinic_id,user_id) where m.clinic_id=p_clinic and (can_read or can_manage)),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',n.user_id,'display_name',n.name)),'[]') from public.staff_display_names n where n.clinic_id=p_clinic and (can_read or can_manage or n.user_id=auth.uid())),
 'appointments',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('patient_id',case when can_patient then a.patient_id else null end) order by starts_at),'[]') from public.clinic_appointments a where a.clinic_id=p_clinic and can_read and starts_at>clock_timestamp()-interval '90 days'),
 -- These areas are not authorized by agenda grants. Restore each only with its own
 -- reviewed permission mapping; workspace.manage is not a financial/clinical shortcut.
 'services','[]'::jsonb,'tasks','[]'::jsonb,'messages','[]'::jsonb,'suppliers','[]'::jsonb,'acts','[]'::jsonb);
end$$;
revoke all on function public.ops_write(uuid,text,jsonb,text),public.ops_patient_search(uuid,text),public.ops_dashboard(uuid) from public,anon;
grant execute on function public.ops_write(uuid,text,jsonb,text),public.ops_patient_search(uuid,text),public.ops_dashboard(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
