-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Después de etapas 1-7.
-- Ejecutar 08A y después 08B. Conserva registros existentes.
-- Agenda/display-name extension; apply once after M10/M11/M13/M14 and team management. Existing records are retained.
begin;
create table public.staff_display_names (
 clinic_id uuid not null references public.clinics(id),
 user_id uuid not null references auth.users(id),
 name text not null check(char_length(btrim(name)) between 2 and 120),
 updated_at timestamptz not null default clock_timestamp(),
 primary key(clinic_id,user_id)
);
alter table public.staff_display_names enable row level security;
revoke all on public.staff_display_names from public,anon,authenticated;
alter table public.clinic_appointments add constraint appointment_patient_clinic
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id);
create function public.ops_patient_search(p_clinic uuid,p_query text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion']) then raise exception 'access_denied';end if;
 if p_query is null or char_length(btrim(p_query)) not between 1 and 120 then raise exception 'patient_search_required';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'species',species) order by name,id),'[]') from
 (select id,name,species from public.vet_patients where clinic_id=p_clinic and strpos(lower(name),lower(btrim(p_query)))>0 order by name,id limit 50) p);
end; $$;
revoke all on function public.ops_patient_search(uuid,text) from public,anon;
grant execute on function public.ops_patient_search(uuid,text) to authenticated;
-- Preserve the M13 plan wrapper when it has already been installed.
do $upgrade$ begin
 execute replace($definition$create or replace function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_service public.clinic_services;v_appointment public.clinic_appointments;v_prof uuid;v_start timestamptz;v_end timestamptz;fp jsonb; v_patient public.vet_patients;
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
 fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_action='display_name' then
 if coalesce(length(btrim(p_data->>'name')),0) not between 2 and 120 then raise exception 'invalid_display_name';end if;
 insert into public.staff_display_names(clinic_id,user_id,name) values(p_clinic,auth.uid(),btrim(p_data->>'name'))
 on conflict(clinic_id,user_id) do update set name=excluded.name,updated_at=clock_timestamp();
 v_id=auth.uid();
 elsif p_action='service' then
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 v_id=nullif(p_data->>'id','')::uuid;
 if v_id is null then
 insert into public.clinic_services(clinic_id,name,price,commission_kind,commission_value) values(p_clinic,btrim(p_data->>'name'),private.inv_money(p_data->>'price'),p_data->>'commission_kind',private.inv_money(p_data->>'commission_value')) returning id into v_id;
 else
 update public.clinic_services set name=btrim(p_data->>'name'),price=private.inv_money(p_data->>'price'),commission_kind=p_data->>'commission_kind',commission_value=private.inv_money(p_data->>'commission_value'),version=version+1,updated_at=clock_timestamp() where id=v_id and clinic_id=p_clinic and version=(p_data->>'version')::int;
 if not found then raise exception 'version_conflict';end if;
 end if;
 elsif p_action='appointment' then
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion','estilista']) then raise exception 'access_denied';end if;
 v_prof=(p_data->>'professional_id')::uuid;v_start=(p_data->>'starts_at')::timestamptz;v_end=(p_data->>'ends_at')::timestamptz;
 if private.has_clinic_role(p_clinic,array['estilista']) and (v_prof<>auth.uid() or p_data->>'kind'<>'estetica') then raise exception 'access_denied';end if;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_prof for update;
 if not found then raise exception 'invalid_professional';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_prof and (p_data->>'kind'='estetica' or role in ('admin','mvz','auxiliar'))) then raise exception 'invalid_professional';end if;
 if exists(select 1 from public.clinic_appointments where clinic_id=p_clinic and professional_id=v_prof and state not in ('cancelado','entregado') and starts_at<v_end and ends_at>v_start) then raise exception 'appointment_overlap';end if;
 if nullif(p_data->>'patient_id','') is not null then
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion']) then raise exception 'access_denied';end if;
 select * into v_patient from public.vet_patients where clinic_id=p_clinic and id=(p_data->>'patient_id')::uuid for share;
 if not found then raise exception 'patient_wrong_clinic';end if;
 end if;
 insert into public.clinic_appointments(clinic_id,patient_id,patient_name,species,kind,professional_id,starts_at,ends_at,notes,created_by)
 values(p_clinic,v_patient.id,coalesce(v_patient.name,p_data->>'patient_name'),coalesce(v_patient.species,p_data->>'species'),p_data->>'kind',v_prof,v_start,v_end,coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 if v_patient.id is null and (coalesce(length(btrim(p_data->>'patient_name')),0) not between 1 and 150 or coalesce(length(btrim(p_data->>'species')),0) not between 1 and 120) then raise exception 'patient_required';end if;
 elsif p_action='appointment_state' then
 v_id=(p_data->>'id')::uuid;
 select * into v_appointment from public.clinic_appointments where id=v_id and clinic_id=p_clinic for update;
 if not found or not (v_appointment.professional_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion'])) then raise exception 'access_denied';end if;
 if v_appointment.version<>(p_data->>'version')::int then raise exception 'version_conflict';end if;
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
 if not found or not (v_appointment.professional_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion'])) then raise exception 'access_denied';end if;
 if v_appointment.version<>(p_data->>'version')::int then raise exception 'version_conflict';end if;
 if v_appointment.state<>'agendado' then raise exception 'appointment_not_scheduled';end if;
 if coalesce(length(btrim(p_data->>'reason')),0) not between 3 and 1000 then raise exception 'appointment_reason_required';end if;
 v_start=(p_data->>'starts_at')::timestamptz; v_end=(p_data->>'ends_at')::timestamptz;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_appointment.professional_id for update;
 if not found then raise exception 'invalid_professional';end if;
 if exists(select 1 from public.clinic_appointments where clinic_id=p_clinic and id<>v_id and professional_id=v_appointment.professional_id and state not in ('cancelado','entregado') and starts_at<v_end and ends_at>v_start) then raise exception 'appointment_overlap';end if;
 update public.clinic_appointments set starts_at=v_start,ends_at=v_end,version=version+1 where id=v_id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'appointment_rescheduled',v_id::text,jsonb_build_object('reason',btrim(p_data->>'reason'),'previous_start',v_appointment.starts_at,'previous_end',v_appointment.ends_at,'starts_at',v_start,'ends_at',v_end,'previous_version',v_appointment.version));
 elsif p_action='task' then
 if nullif(p_data->>'assigned_to','') is not null then
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=(p_data->>'assigned_to')::uuid for share;
 if not found then raise exception 'invalid_professional';end if;
 end if;
 insert into public.clinic_tasks(clinic_id,title,assigned_to,priority,created_by) values(p_clinic,p_data->>'title',nullif(p_data->>'assigned_to','')::uuid,p_data->>'priority',auth.uid()) returning id into v_id;
 elsif p_action='task_complete' then
 v_id=(p_data->>'id')::uuid;
 update public.clinic_tasks set completed_at=clock_timestamp(),completed_by=auth.uid() where id=v_id and clinic_id=p_clinic and completed_at is null and (assigned_to=auth.uid() or assigned_to is null or created_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']));
 if not found then raise exception 'access_denied';end if;
 elsif p_action='message' then
 insert into public.clinic_messages(clinic_id,category,body,author_id) values(p_clinic,p_data->>'category',p_data->>'body',auth.uid()) returning id into v_id;
 elsif p_action='supplier' then
 if not private.has_clinic_role(p_clinic,array['admin','recepcion']) then raise exception 'access_denied';end if;
 insert into public.clinic_suppliers(clinic_id,name,phone,notes,created_by) values(p_clinic,p_data->>'name',coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 elsif p_action='service_act' then
 select * into v_service from public.clinic_services where id=(p_data->>'service_id')::uuid and clinic_id=p_clinic and active for share;
 if not found then raise exception 'service_required';end if;
 v_prof=(p_data->>'professional_id')::uuid;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_prof for share;
 if not found then raise exception 'invalid_professional';end if;
 if not (v_prof=auth.uid() or private.has_clinic_role(p_clinic,array['admin','recepcion'])) then raise exception 'access_denied';end if;
 if nullif(p_data->>'appointment_id','') is not null and not exists(select 1 from public.clinic_appointments where id=(p_data->>'appointment_id')::uuid and clinic_id=p_clinic and professional_id=v_prof) then raise exception 'invalid_appointment';end if;
 insert into public.clinic_service_acts(clinic_id,service_id,professional_id,appointment_id,name,service_version,price,commission,commission_kind,commission_value,created_by) values(p_clinic,v_service.id,v_prof,nullif(p_data->>'appointment_id','')::uuid,v_service.name,v_service.version,v_service.price,case when v_service.commission_kind='porcentaje' then round(v_service.price*v_service.commission_value/100,2) else v_service.commission_value end,v_service.commission_kind,v_service.commission_value,auth.uid()) returning id into v_id;
 else raise exception 'unknown_operation';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'ops_'||p_action,v_id::text);
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
$definition$,
 'create or replace function public.ops_write(',
 case when to_regprocedure('public.ops_write_before_plans(uuid,text,jsonb,text)') is not null
 then 'create or replace function public.ops_write_before_plans('
 else 'create or replace function public.ops_write(' end);
end $upgrade$;
create or replace function public.ops_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object(
 'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'role',role,'display_name',(select n.name from public.staff_display_names n where n.clinic_id=p_clinic and n.user_id=public.clinic_members.user_id))),'[]') from public.clinic_members where clinic_id=p_clinic),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',n.user_id,'display_name',n.name)),'[]') from public.staff_display_names n where n.clinic_id=p_clinic),
 'services',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('price',s.price::text,'commission_value',s.commission_value::text)),'[]') from public.clinic_services s where clinic_id=p_clinic),
 'appointments',(select coalesce(jsonb_agg(to_jsonb(a) order by starts_at),'[]') from public.clinic_appointments a where clinic_id=p_clinic and (private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion']) or professional_id=auth.uid()) and starts_at>clock_timestamp()-interval '90 days'),
 'tasks',(select coalesce(jsonb_agg(to_jsonb(t) order by created_at desc),'[]') from public.clinic_tasks t where clinic_id=p_clinic and (assigned_to is null or assigned_to=auth.uid() or created_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
 'messages',(select coalesce(jsonb_agg(to_jsonb(m) order by created_at),'[]') from (select * from public.clinic_messages where clinic_id=p_clinic order by created_at desc limit 100) m),
 'suppliers',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.clinic_suppliers s where clinic_id=p_clinic and private.has_clinic_role(p_clinic,array['admin','recepcion'])),
 'acts',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('price',a.price::text,'commission',a.commission::text,'paid',exists(select 1 from public.inventory_sale_lines l where l.service_act_id=a.id and not exists(select 1 from public.inventory_sale_reversals r where r.sale_id=l.sale_id)))),'[]') from public.clinic_service_acts a where clinic_id=p_clinic and (professional_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin','recepcion']))));
end$$;
create or replace function public.att_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object('settings',(select to_jsonb(s) from public.attendance_settings s where clinic_id=p_clinic),'consented',exists(select 1 from public.attendance_consents c join public.attendance_settings s using(clinic_id) where c.clinic_id=p_clinic and c.user_id=auth.uid() and c.settings_version=s.version),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',n.user_id,'display_name',n.name)),'[]') from public.staff_display_names n where n.clinic_id=p_clinic and (n.user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
 'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('effective_at',coalesce((select c.corrected_at from public.attendance_corrections c where c.event_id=e.id order by c.created_at desc,c.id desc limit 1),e.server_at)) order by server_at desc),'[]') from public.attendance_events e where clinic_id=p_clinic and (user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
 'corrections',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.attendance_corrections c join public.attendance_events e on e.id=c.event_id where e.clinic_id=p_clinic and (e.user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))));
end$$;
-- Preserve the complete existing export, including own AI history and payment records.
alter function private.clinic_snapshot(uuid) rename to clinic_snapshot_before_agenda;
revoke all on function private.clinic_snapshot_before_agenda(uuid) from public,anon,authenticated;
create function private.clinic_snapshot(p_clinic uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare snapshot jsonb;
begin
 snapshot=private.clinic_snapshot_before_agenda(p_clinic)::jsonb;
 snapshot=jsonb_set(snapshot,'{tables,staff_display_names}',(select coalesce(jsonb_agg(to_jsonb(n)),'[]') from public.staff_display_names n where n.clinic_id=p_clinic));
 return snapshot::text;
end $$;
revoke all on function private.clinic_snapshot(uuid) from public,anon,authenticated;
commit;

notify pgrst, 'reload schema';
select '08A COMPLETADO: citas vinculadas y nombres del equipo' as resultado;
-- FIN COMPLETO 08A
