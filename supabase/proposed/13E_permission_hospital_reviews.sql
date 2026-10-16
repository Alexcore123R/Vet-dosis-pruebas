-- LOCAL CANDIDATE 13E: typed review orders, not medication cutover or deployable UI.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
alter table public.hospital_tasks add column procedure_type_id uuid;
alter table public.hospital_tasks add constraint hospital_task_procedure_clinic foreign key(clinic_id,procedure_type_id) references private.procedure_types(clinic_id,id);
alter table public.hospital_tasks add column authority_grant_id uuid references private.member_permission_grants(id);
alter table public.hospital_tasks add constraint hospital_task_authority_pair check((procedure_type_id is null)=(authority_grant_id is null));
-- Historical rows stay unbound. No guessed mapping, professional verification or grant migration.
create function private.hospital_order_permission(p_clinic uuid,p_code text,p_procedure uuid,p_professional boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 g=private.permission_require(p_clinic,p_code,p_procedure);
 if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 if p_professional and not private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()) then raise exception 'verified_professional_required';end if;
 return g;
end$$;
revoke all on function private.hospital_order_permission(uuid,text,uuid,boolean) from public,anon,authenticated;
create function public.hospital_review_schedule(p_clinic_id uuid,p_stay_id uuid,p_procedure_id uuid,p_label text,p_instructions text,p_times jsonb,p_escalation_minutes integer,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;fp jsonb;stay public.hospital_stays;instant jsonb;due timestamptz;first_id uuid;g uuid;p_kind text='revision';
begin
 perform 1 from public.clinics where clinics.id=p_clinic_id for update;
 perform private.hospital_order_permission(p_clinic_id,'hospital.read',null,false);
 g=private.hospital_order_permission(p_clinic_id,'hospital.schedule',null,true);
 if not exists(select 1 from private.procedure_types where clinic_id=p_clinic_id and procedure_types.id=p_procedure_id and active) then raise exception 'active_procedure_required';end if;
 fp=jsonb_build_object('kind','hospital_review_schedule','procedure',p_procedure_id,'stay',p_stay_id,'type',p_kind,'label',p_label,'instructions',p_instructions,'times',p_times,'escalation',p_escalation_minutes);
 id=private.vet_receipt(p_clinic_id,p_operation_id,fp);if id is not null then return id;end if;
 select * into stay from public.hospital_stays where clinic_id=p_clinic_id and hospital_stays.id=p_stay_id for update;
 if not found or stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 -- A pre-cutover writer can still hold the stay lock: recheck after that wait.
 g=private.hospital_order_permission(p_clinic_id,'hospital.schedule',null,true);
 perform private.hospital_order_permission(p_clinic_id,'hospital.read',null,false);
 if p_kind is null or p_kind not in ('medicacion','revision') or p_label is null or length(btrim(p_label)) not between 1 and 300 or p_instructions is null or length(btrim(p_instructions)) not between 1 and 4000 then raise exception 'invalid_order';end if;
 if p_escalation_minutes is null or p_escalation_minutes not between 1 and 120 then raise exception 'invalid_escalation';end if;
 if jsonb_typeof(p_times) is distinct from 'array' then raise exception 'invalid_times';end if;
 if jsonb_array_length(p_times) not between 1 and 200 then raise exception 'invalid_times';end if;
 for instant in select * from jsonb_array_elements(p_times) loop
  if jsonb_typeof(instant) is distinct from 'string' or (instant#>>'{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then raise exception 'invalid_instant';end if;
  due=(instant#>>'{}')::timestamptz;
  if due<=clock_timestamp() then raise exception 'past_order_time';end if;
 end loop;
 if (select count(distinct (x#>>'{}')::timestamptz) from jsonb_array_elements(p_times) x)<>jsonb_array_length(p_times) then raise exception 'duplicate_times';end if;
 for instant in select * from jsonb_array_elements(p_times) loop
  insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id)
  values(p_clinic_id,p_stay_id,p_kind,btrim(p_label),btrim(p_instructions),(instant#>>'{}')::timestamptz,p_escalation_minutes,auth.uid(),p_procedure_id,g) returning hospital_tasks.id into id;
  first_id=coalesce(first_id,id);
  insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic_id,auth.uid(),'hospital_task_prescribed',id,jsonb_build_object('procedure_type_id',p_procedure_id,'permission_grant_id',g));
 end loop;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fp,first_id);
 return first_id;
end $$;

-- The free-text route cannot produce either medication applications or untyped review orders.
create or replace function public.hospital_prescribe(p_clinic_id uuid,p_stay_id uuid,p_kind text,p_label text,p_instructions text,p_times jsonb,p_escalation_minutes integer,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_kind='medicacion' then raise exception 'structured_medication_order_required';end if;
 raise exception 'typed_review_order_required';
end$$;
create or replace function public.hospital_task_action(p_clinic_id uuid,p_task_id uuid,p_expected_version integer,p_action text,p_minutes integer default null,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare t public.hospital_tasks;s public.hospital_stays;g uuid;code text;begin
 perform 1 from public.clinics where clinics.id=p_clinic_id for update;
 if p_action is null or p_action not in ('perform','snooze','cancel') then raise exception 'invalid_action';end if;
 -- Read authorization precedes all task existence/state disclosures and retries.
 perform private.hospital_order_permission(p_clinic_id,'hospital.read',null,false);
 select * into t from public.hospital_tasks where clinic_id=p_clinic_id and id=p_task_id;
 if not found then raise exception 'task_not_found';end if;
 select * into s from public.hospital_stays where clinic_id=p_clinic_id and id=t.stay_id for update;
 select * into t from public.hospital_tasks where clinic_id=p_clinic_id and id=p_task_id for update;
 if t.kind='medicacion' or t.prescription_item_id is not null then raise exception 'structured_medication_action_required';end if;
 code=case p_action when 'perform' then 'procedure.perform' when 'snooze' then 'hospital.report' else 'hospital.schedule' end;
 if p_action='perform' and (t.procedure_type_id is null or t.authority_grant_id is null) then raise exception 'legacy_review_reauthorization_required';end if;
 g=private.hospital_order_permission(p_clinic_id,code,case when p_action='perform' then t.procedure_type_id else null end,p_action<>'snooze');
 -- First confirmation wins, including concurrent attempts by the same person.
 if t.state='done' then raise exception 'task_already_confirmed';end if;
 if s.discharged_at is not null then raise exception 'stay_inactive';end if;
 if t.state<>'pending' then raise exception 'task_not_pending';end if;
 if t.version is distinct from p_expected_version then raise exception 'version_conflict';end if;
 if p_action='perform' then
  if t.due_at>clock_timestamp() or t.snoozed_until>clock_timestamp() then raise exception 'task_not_due';end if;
  update public.hospital_tasks set state='done',performed_by=auth.uid(),performed_at=clock_timestamp(),version=version+1 where id=t.id;
 elsif p_action='snooze' then
  if t.due_at>clock_timestamp() then raise exception 'task_not_due';end if;
  if t.snooze_count>=3 then raise exception 'snooze_limit';end if;
  if p_minutes is null or p_minutes not between 1 and 30 or p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'invalid_snooze';end if;
  update public.hospital_tasks set snoozed_until=clock_timestamp()+make_interval(mins=>p_minutes),snooze_count=snooze_count+1,snooze_reason=btrim(p_reason),version=version+1 where id=t.id;
 else
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'reason_required';end if;
  update public.hospital_tasks set state='cancelled',cancelled_by=auth.uid(),cancelled_at=clock_timestamp(),cancel_reason=btrim(p_reason),version=version+1 where id=t.id;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic_id,auth.uid(),'hospital_task_'||p_action,t.id,jsonb_build_object('procedure_type_id',t.procedure_type_id,'permission_grant_id',g,'previous_version',t.version,'version',t.version+1,'reason',p_reason));
end$$;
revoke all on function public.hospital_review_schedule(uuid,uuid,uuid,text,text,jsonb,integer,text) from public,anon;
grant execute on function public.hospital_review_schedule(uuid,uuid,uuid,text,text,jsonb,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
