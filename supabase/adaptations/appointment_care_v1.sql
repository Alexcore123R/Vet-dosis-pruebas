-- Additive candidate: review remote M4/M9 + explicit grants before applying once.
-- Does not replace ops_write, hospital discharge, sales, permissions or beta policy.
begin;
do $$begin
 if (select not admissions_enabled and not enforcement_enabled from private.beta_policy) is distinct from true
 or (select enforcement_enabled from private.permission_policy) is distinct from false then
  raise exception 'closed_beta_and_dormant_permissions_required';
 end if;
end$$;
create unique index appointment_care_clinic_key on public.clinic_appointments(clinic_id,id);
create table public.appointment_care_records(
 id uuid primary key default gen_random_uuid(), clinic_id uuid not null, appointment_id uuid not null,
 patient_id uuid, action text not null check(action in ('admit','ready','deliver')),
 details jsonb not null check(jsonb_typeof(details)='object'), clinical_event_id uuid references public.vet_patient_events(id),
 recorded_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,appointment_id) references public.clinic_appointments(clinic_id,id),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 unique(appointment_id,action));
alter table public.appointment_care_records enable row level security;
revoke all on public.appointment_care_records from public,anon,authenticated;
create trigger appointment_care_immutable before update or delete on public.appointment_care_records
 for each row execute function private.inv_history_guard();
create function private.appointment_care_guard(p_clinic uuid,p_manage boolean)
returns void language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 if auth.uid() is null then raise exception 'access_denied';end if;
 if p_manage then
  perform 1 from public.clinics where id=p_clinic for update;
  perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 g=private.permission_require(p_clinic,'appointment.read');
 if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 if p_manage then
  g=private.permission_require(p_clinic,'appointment.manage');
  if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 end if;
end$$;
revoke all on function private.appointment_care_guard(uuid,boolean) from public,anon,authenticated;
create function public.appointment_care_snapshot(p_clinic uuid,p_appointments uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text;d date;can_patient boolean;can_manage boolean;can_clinical boolean;begin
 perform private.appointment_care_guard(p_clinic,false);
 if p_appointments is null or cardinality(p_appointments)>100 then raise exception 'invalid_batch';end if;
 select coalesce(timezone,'America/Mexico_City') into tz from public.inventory_clinic_settings where clinic_id=p_clinic;
 tz=coalesce(tz,'America/Mexico_City');d=(statement_timestamp() at time zone tz)::date;
 can_patient=private.permission_effective(p_clinic,auth.uid(),'patient.read') is not null;
 can_manage=private.permission_effective(p_clinic,auth.uid(),'appointment.manage') is not null;
 can_clinical=can_patient and private.permission_effective(p_clinic,auth.uid(),'patient.write') is not null
  and exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role::text in ('admin','mvz'));
 return jsonb_build_object('schema_version',1,'clinic_id',p_clinic,'day',d,'timezone',tz,
  'day_start',d::timestamp at time zone tz,'day_end',(d+1)::timestamp at time zone tz,
  'appointments',(select coalesce(jsonb_agg(jsonb_build_object('appointment_id',a.id,
   'can_manage',can_manage and (a.patient_id is null or can_patient),
   'can_close',can_manage and (a.patient_id is null or can_patient) and (a.kind='estetica' or (can_clinical and a.patient_id is not null)),
   'records',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'action',r.action,'details',r.details,
    'recorded_by',r.recorded_by,'created_at',r.created_at,'clinical_recorded',r.clinical_event_id is not null)
    order by r.created_at,r.id),'[]') from public.appointment_care_records r where r.clinic_id=p_clinic and r.appointment_id=a.id))),'[]')
   from public.clinic_appointments a where a.clinic_id=p_clinic and a.id=any(p_appointments)
    and (a.professional_id=auth.uid() or exists(select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=auth.uid() and m.role::text in ('admin','mvz','auxiliar','recepcion')))));
end$$;
create function public.appointment_care_write(p_clinic uuid,p_appointment uuid,p_version integer,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.clinic_appointments;r uuid;event_id uuid;fp jsonb;field text;val text;doc jsonb='{}';
 target_state text;g uuid;nested_op text;pickup text;clinical_day date;plan text;tz text;visit_reason text;
begin
 perform private.appointment_care_guard(p_clinic,true);
 select * into a from public.clinic_appointments where clinic_id=p_clinic and id=p_appointment for update;
 if not found or not (a.professional_id=auth.uid() or exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role::text in ('admin','mvz','auxiliar','recepcion'))) then raise exception 'access_denied';end if;
 if a.patient_id is not null then
  g=private.permission_require(p_clinic,'patient.read');
  if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 end if;
 if p_action is null or p_action not in ('admit','ready','deliver') or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>18000 then raise exception 'invalid_data';end if;
 if p_action='ready' and a.kind='consulta' then
  if a.patient_id is null then raise exception 'care_patient_required';end if;
  if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role::text in ('admin','mvz')) then raise exception 'clinical_role_required';end if;
  g=private.permission_require(p_clinic,'patient.write');
  if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 end if;
 fp=jsonb_build_object('kind','appointment_care','appointment',p_appointment,'version',p_version,'action',p_action,'data',p_data);
 r=private.vet_receipt(p_clinic,p_operation,fp);
 -- A replay rechecks all current permissions above before returning its receipt.
 if r is not null then return r;end if;
 if a.version is distinct from p_version then raise exception 'version_conflict';end if;
 if exists(select 1 from public.appointment_care_records where appointment_id=a.id and action=p_action) then raise exception 'care_already_recorded';end if;
 foreach field in array case p_action
  when 'admit' then array['reason','belongings','authorized_services','authorized_by','pickup_person','budget_reference']
  when 'ready' then array['instructions','treatment','followup','clinical_date']
  else array['released_to','pickup_authorization','belongings_outcome'] end loop
  if p_data ? field and jsonb_typeof(p_data->field) is distinct from 'string' then raise exception 'invalid_data';end if;
  val=btrim(coalesce(p_data->>field,''));
  if length(val)>(case when field in ('instructions','treatment','followup') then 1200 else 500 end) then raise exception 'invalid_data';end if;
  doc=doc||jsonb_build_object(field,val);
 end loop;
 if p_action='admit' then
  if a.state not in ('agendado','en_atencion') then raise exception 'invalid_transition';end if;
  foreach field in array array['reason','belongings','authorized_services','authorized_by','pickup_person'] loop
   if doc->>field='' then raise exception 'care_required';end if;
  end loop;
  if p_data ? 'budget_accepted' and jsonb_typeof(p_data->'budget_accepted') is distinct from 'boolean' then raise exception 'invalid_data';end if;
  doc=doc||jsonb_build_object('budget_accepted',coalesce((p_data->>'budget_accepted')::boolean,false));
  if doc->'budget_accepted'='true'::jsonb and doc->>'budget_reference'='' then raise exception 'care_budget_reference_required';end if;
  if a.state='agendado' then target_state='en_atencion';end if;
 elsif p_action='ready' then
  if a.state not in ('en_atencion','listo') then raise exception 'invalid_transition';end if;
  if doc->>'instructions'='' then raise exception 'care_required';end if;
  if a.kind='consulta' then
   if doc->>'clinical_date' !~ '^\d{4}-\d{2}-\d{2}$' or doc->>'clinical_date'='' then raise exception 'care_date_required';end if;
   clinical_day=(doc->>'clinical_date')::date;
   select coalesce(timezone,'America/Mexico_City') into tz from public.inventory_clinic_settings where clinic_id=p_clinic;
   if clinical_day>(statement_timestamp() at time zone coalesce(tz,'America/Mexico_City'))::date then raise exception 'care_date_required';end if;
   plan='Indicaciones: '||(doc->>'instructions')||E'\nTratamiento indicado: '||(doc->>'treatment')||E'\nSeguimiento: '||(doc->>'followup');
   nested_op=md5(p_operation||':clinical')||substr(md5(p_operation||':clinical2'),1,16);
   select left(details->>'reason',300) into visit_reason from public.appointment_care_records where appointment_id=a.id and action='admit';
   event_id=public.add_vet_patient_event(p_clinic,a.patient_id,'soap',jsonb_build_object(
    'date',clinical_day::text,'reason',coalesce(visit_reason,'Cierre de consulta'),'species_template',a.species,
    'subjective','','objective','','assessment','','plan',plan,
    'record_type','care_discharge','appointment_id',a.id),nested_op);
   -- Clinical text stays solely in the clinical event, never in the operational snapshot.
   doc=jsonb_build_object('clinical_recorded',true);
  elsif doc->>'treatment'<>'' or doc->>'clinical_date'<>'' then raise exception 'clinical_data_not_allowed';
  end if;
  if a.state='en_atencion' then target_state='listo';end if;
 else
  if a.state<>'listo' then raise exception 'invalid_transition';end if;
  if not exists(select 1 from public.appointment_care_records where appointment_id=a.id and action='ready') then raise exception 'care_close_required';end if;
  if doc->>'released_to'='' or doc->>'belongings_outcome'='' or p_data->'pickup_verified' is distinct from 'true'::jsonb or p_data->'instructions_delivered' is distinct from 'true'::jsonb then raise exception 'care_delivery_confirmation_required';end if;
  select details->>'pickup_person' into pickup from public.appointment_care_records where appointment_id=a.id and action='admit';
  if (pickup is null or lower(pickup)<>lower(doc->>'released_to')) and doc->>'pickup_authorization'='' then raise exception 'care_pickup_authorization_required';end if;
  doc=doc||jsonb_build_object('pickup_verified',true,'instructions_delivered',true);
  target_state='entregado';
 end if;
 if target_state is not null then
  nested_op=md5(p_operation||':state')||substr(md5(p_operation||':state2'),1,16);
  perform public.ops_write(p_clinic,'appointment_state',jsonb_build_object('id',a.id,'version',a.version,'state',target_state),nested_op);
 else
  -- Backfill of a legacy active/ready appointment is versioned without changing its state.
  update public.clinic_appointments set version=version+1 where id=a.id and clinic_id=p_clinic;
 end if;
 insert into public.appointment_care_records(clinic_id,appointment_id,patient_id,action,details,clinical_event_id,recorded_by)
 values(p_clinic,a.id,a.patient_id,p_action,doc,event_id,auth.uid()) returning id into r;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,r);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'care_'||p_action,r::text);
 return r;
end$$;
revoke all on function public.appointment_care_snapshot(uuid,uuid[]),public.appointment_care_write(uuid,uuid,integer,text,jsonb,text) from public,anon;
grant execute on function public.appointment_care_snapshot(uuid,uuid[]),public.appointment_care_write(uuid,uuid,integer,text,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
