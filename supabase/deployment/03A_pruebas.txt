-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Ejecutar 03A, 03B, 03C en ese orden.
-- Apply once after M2 and M4. No clinical doses or protocols are seeded.
begin;
create table public.hospital_stays (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,
 cage text not null check(length(btrim(cage)) between 1 and 80),
 admitted_at timestamptz not null default now(),admitted_by uuid not null references auth.users(id),
 discharged_at timestamptz,discharged_by uuid references auth.users(id),discharge_reason text,
 version integer not null default 1,unique(clinic_id,id),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id)
);
create unique index hospital_cage_occupied on public.hospital_stays(clinic_id,lower(btrim(cage))) where discharged_at is null;
create unique index hospital_patient_admitted on public.hospital_stays(clinic_id,patient_id) where discharged_at is null;
create table public.hospital_tasks (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,stay_id uuid not null,
 kind text not null check(kind in ('medicacion','revision')),
 label text not null check(length(btrim(label)) between 1 and 300),
 instructions text not null check(length(btrim(instructions)) between 1 and 4000),
 due_at timestamptz not null,escalation_minutes integer not null check(escalation_minutes between 1 and 120),
 state text not null default 'pending' check(state in ('pending','done','cancelled')),
 version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 performed_by uuid references auth.users(id),performed_at timestamptz,
 snoozed_until timestamptz,snooze_count integer not null default 0 check(snooze_count between 0 and 3),snooze_reason text,
 cancelled_by uuid references auth.users(id),cancelled_at timestamptz,cancel_reason text,
 foreign key(clinic_id,stay_id) references public.hospital_stays(clinic_id,id)
);
create index hospital_tasks_sheet on public.hospital_tasks(clinic_id,stay_id,due_at);
revoke all on public.hospital_stays,public.hospital_tasks from public,anon,authenticated;
grant select on public.hospital_stays,public.hospital_tasks to authenticated;
alter table public.hospital_stays enable row level security;
alter table public.hospital_tasks enable row level security;
create policy hospital_stay_read on public.hospital_stays for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create policy hospital_task_read on public.hospital_tasks for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar']));
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 return jsonb_build_object('stays',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('vet_patients',jsonb_build_object('name',p.name,'species',p.species)) order by s.cage) from public.hospital_stays s join public.vet_patients p on p.id=s.patient_id and p.clinic_id=s.clinic_id where s.clinic_id=p_clinic_id and s.discharged_at is null),'[]'::jsonb),
 'tasks',coalesce((select jsonb_agg(to_jsonb(t) order by t.due_at) from public.hospital_tasks t join public.hospital_stays s on s.id=t.stay_id and s.clinic_id=t.clinic_id where t.clinic_id=p_clinic_id and s.discharged_at is null),'[]'::jsonb));
end $$;
create function public.hospital_admit(p_clinic_id uuid,p_patient_id uuid,p_cage text,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;fp jsonb;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
 fp=jsonb_build_object('kind','hospital_admit','patient',p_patient_id,'cage',p_cage);
 id=private.vet_receipt(p_clinic_id,p_operation_id,fp);if id is not null then return id;end if;
 if p_cage is null or length(btrim(p_cage)) not between 1 and 80 then raise exception 'invalid_cage';end if;
 if not exists(select 1 from public.vet_patients where clinic_id=p_clinic_id and vet_patients.id=p_patient_id) then raise exception 'patient_wrong_clinic';end if;
 insert into public.hospital_stays(clinic_id,patient_id,cage,admitted_by) values(p_clinic_id,p_patient_id,btrim(p_cage),auth.uid()) returning hospital_stays.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fp,id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_admitted',id);
 return id;
end $$;
create function public.hospital_prescribe(p_clinic_id uuid,p_stay_id uuid,p_kind text,p_label text,p_instructions text,p_times jsonb,p_escalation_minutes integer,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;fp jsonb;stay public.hospital_stays;instant jsonb;due timestamptz;first_id uuid;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
 fp=jsonb_build_object('kind','hospital_prescribe','stay',p_stay_id,'type',p_kind,'label',p_label,'instructions',p_instructions,'times',p_times,'escalation',p_escalation_minutes);
 id=private.vet_receipt(p_clinic_id,p_operation_id,fp);if id is not null then return id;end if;
 select * into stay from public.hospital_stays where clinic_id=p_clinic_id and hospital_stays.id=p_stay_id for update;
 if not found or stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if p_kind is null or p_kind not in ('medicacion','revision') or p_label is null or length(btrim(p_label)) not between 1 and 300 or p_instructions is null or length(btrim(p_instructions)) not between 1 and 4000 then raise exception 'invalid_order';end if;
 if p_escalation_minutes is null or p_escalation_minutes not between 1 and 120 then raise exception 'invalid_escalation';end if;
 if jsonb_typeof(p_times) is distinct from 'array' then raise exception 'invalid_times';end if;
 if jsonb_array_length(p_times) not between 1 and 200 then raise exception 'invalid_times';end if;
 for instant in select * from jsonb_array_elements(p_times) loop
  if jsonb_typeof(instant) is distinct from 'string' or (instant#>>'{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then raise exception 'invalid_instant';end if;
  due=(instant#>>'{}')::timestamptz;
  if due<=now() then raise exception 'past_order_time';end if;
 end loop;
 if (select count(distinct (x#>>'{}')::timestamptz) from jsonb_array_elements(p_times) x)<>jsonb_array_length(p_times) then raise exception 'duplicate_times';end if;
 for instant in select * from jsonb_array_elements(p_times) loop
  insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by)
  values(p_clinic_id,p_stay_id,p_kind,btrim(p_label),btrim(p_instructions),(instant#>>'{}')::timestamptz,p_escalation_minutes,auth.uid()) returning hospital_tasks.id into id;
  first_id=coalesce(first_id,id);
  insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_task_prescribed',id);
 end loop;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fp,first_id);
 return first_id;
end $$;
create function public.hospital_task_action(p_clinic_id uuid,p_task_id uuid,p_expected_version integer,p_action text,p_minutes integer default null,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare task public.hospital_tasks;stay public.hospital_stays;stay_id uuid;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz','auxiliar']) then raise exception 'clinical_role_required';end if;
 if p_action is null or p_action not in ('perform','snooze','cancel') then raise exception 'invalid_action';end if;
 select t.stay_id into stay_id from public.hospital_tasks t where t.clinic_id=p_clinic_id and t.id=p_task_id;
 if stay_id is null then raise exception 'task_not_found';end if;
 -- All mutations lock the stay before tasks, including discharge.
 select * into stay from public.hospital_stays s where s.id=stay_id and s.clinic_id=p_clinic_id for update;
 select * into task from public.hospital_tasks t where t.id=p_task_id and t.clinic_id=p_clinic_id for update;
 if p_action='perform' and task.state='done' and task.performed_by=auth.uid() then return;end if;
 if stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if task.state<>'pending' then raise exception 'task_not_pending';end if;
 if p_expected_version is null or task.version<>p_expected_version then raise exception 'version_conflict';end if;
 if p_action='perform' then
  -- Scheduling does not authorize an early administration.
  if task.due_at>now() then raise exception 'task_not_due';end if;
  update public.hospital_tasks set state='done',performed_by=auth.uid(),performed_at=now(),version=version+1 where id=p_task_id;
 elsif p_action='snooze' then
  if task.due_at>now() then raise exception 'task_not_due';end if;
  if task.snooze_count>=3 then raise exception 'snooze_limit';end if;
  if p_minutes is null or p_minutes not between 1 and 30 or p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'invalid_snooze';end if;
  update public.hospital_tasks set snoozed_until=now()+make_interval(mins=>p_minutes),snooze_count=snooze_count+1,snooze_reason=btrim(p_reason),version=version+1 where id=p_task_id;
 else
  if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'reason_required';end if;
  update public.hospital_tasks set state='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason=btrim(p_reason),version=version+1 where id=p_task_id;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_task_'||p_action,p_task_id);
end $$;
create function public.hospital_discharge(p_clinic_id uuid,p_stay_id uuid,p_expected_version integer,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare stay public.hospital_stays;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz']) then raise exception 'physician_required';end if;
 if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'reason_required';end if;
 select * into stay from public.hospital_stays where clinic_id=p_clinic_id and id=p_stay_id for update;
 if not found or stay.discharged_at is not null then raise exception 'stay_inactive';end if;
 if p_expected_version is null or stay.version<>p_expected_version then raise exception 'version_conflict';end if;
 update public.hospital_stays set discharged_at=now(),discharged_by=auth.uid(),discharge_reason=btrim(p_reason),version=version+1 where id=p_stay_id;
 update public.hospital_tasks set state='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason='Alta: '||btrim(p_reason),version=version+1 where stay_id=p_stay_id and clinic_id=p_clinic_id and state='pending';
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'hospital_discharged',p_stay_id);
end $$;
revoke all on function public.hospital_snapshot(uuid),public.hospital_admit(uuid,uuid,text,text),public.hospital_prescribe(uuid,uuid,text,text,text,jsonb,integer,text),public.hospital_task_action(uuid,uuid,integer,text,integer,text),public.hospital_discharge(uuid,uuid,integer,text) from public,anon;
grant execute on function public.hospital_snapshot(uuid),public.hospital_admit(uuid,uuid,text,text),public.hospital_prescribe(uuid,uuid,text,text,text,jsonb,integer,text),public.hospital_task_action(uuid,uuid,integer,text,integer,text),public.hospital_discharge(uuid,uuid,integer,text) to authenticated;
commit;

notify pgrst, 'reload schema';
select '03A COMPLETADO: hospitalizacion' as resultado;
-- FIN COMPLETO 03A
