-- Additive candidate. Uses caller RLS on clinical events: never reopens legacy event writes.
-- Review M4/M9, explicit clinical grants and professional verification before applying once.
begin;
do $$begin
 if (select not admissions_enabled and not enforcement_enabled from private.beta_policy) is distinct from true
 or (select enforcement_enabled from private.permission_policy) is distinct from false then
  raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create function private.booklet_access(c uuid,w boolean default false,medical boolean default false)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare k text;g uuid;verified boolean=false;begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=c and user_id=auth.uid() and role::text in ('admin','mvz','auxiliar')) then return false;end if;
 foreach k in array array['patient.read','clinical.read'] || case when w then array['patient.write'] else array[]::text[] end || case when medical then array['clinical.authorize'] else array[]::text[] end loop
  g=private.permission_effective(c,auth.uid(),k);
  if g is null or not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then return false;end if;
 end loop;
 if medical then
  if not exists(select 1 from public.clinic_members where clinic_id=c and user_id=auth.uid() and role::text in ('admin','mvz')) then return false;end if;
  if to_regprocedure('private.clinical_professional_at(uuid,uuid,timestamp with time zone)') is not null then
   execute 'select private.clinical_professional_at($1,$2,clock_timestamp())' into verified using c,auth.uid();
  end if;
  return coalesce(verified,false);
 end if;
 return true;
end$$;
revoke all on function private.booklet_access(uuid,boolean,boolean) from public,anon;
grant execute on function private.booklet_access(uuid,boolean,boolean) to authenticated;
create function private.booklet_schedule_access(c uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare k text;g uuid;begin
 if not private.booklet_access(c) then return false;end if;
 foreach k in array array['appointment.read','appointment.manage'] loop
  g=private.permission_effective(c,auth.uid(),k);
  if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then return false;end if;
 end loop;return true;
end$$;
revoke all on function private.booklet_schedule_access(uuid) from public,anon;
grant execute on function private.booklet_schedule_access(uuid) to authenticated;
-- Serialize mutation checks with clinic/member changes and professional revocations.
create function private.booklet_locked_access(c uuid,w boolean,medical boolean,scheduling boolean default false)
returns boolean language plpgsql volatile security definer set search_path='' as $$begin
 if scheduling then
  if not private.booklet_schedule_access(c) then return false;end if;
 elsif not private.booklet_access(c,w,medical) then return false;end if;
 perform 1 from public.clinics where id=c for update;
 perform 1 from public.clinic_members where clinic_id=c and user_id=auth.uid() for share;
 if medical then perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));end if;
 if scheduling then return private.booklet_schedule_access(c);end if;
 return private.booklet_access(c,w,medical);
end$$;
revoke all on function private.booklet_locked_access(uuid,boolean,boolean,boolean) from public,anon;
grant execute on function private.booklet_locked_access(uuid,boolean,boolean,boolean) to authenticated;
create table public.preventive_evidence(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,
 event_id uuid not null references public.vet_patient_events(id),label text not null check(length(btrim(label)) between 1 and 150),
 mime text not null check(mime in ('image/jpeg','image/png','application/pdf')),
 content bytea not null check(octet_length(content) between 6 and 3145728),
 operation text not null check(operation ~ '^[a-f0-9]{48}$'),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 unique(clinic_id,created_by,operation),
 check((mime='image/jpeg' and substring(content from 1 for 3)=decode('ffd8ff','hex'))
  or (mime='image/png' and substring(content from 1 for 8)=decode('89504e470d0a1a0a','hex'))
  or (mime='application/pdf' and substring(content from 1 for 5)=decode('255044462d','hex'))));
create table public.preventive_plans(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,
 event_id uuid references public.vet_patient_events(id),type text not null check(type in ('vacuna','desparasitación')),
 coverage text not null check(length(btrim(coverage)) between 1 and 1000),due_date date not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 operation text not null check(operation ~ '^[a-f0-9]{48}$'),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),unique(clinic_id,created_by,operation));
create table public.preventive_plan_retirements(
 plan_id uuid primary key references public.preventive_plans(id),clinic_id uuid not null,patient_id uuid not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 operation text not null check(operation ~ '^[a-f0-9]{48}$'),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),unique(clinic_id,created_by,operation));
create table public.preventive_appointment_links(
 plan_id uuid not null references public.preventive_plans(id),appointment_id uuid not null references public.clinic_appointments(id),
 clinic_id uuid not null,patient_id uuid not null,operation text not null check(operation ~ '^[a-f0-9]{48}$'),
 request jsonb not null check(jsonb_typeof(request)='object' and octet_length(request::text)<=10000),created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 primary key(plan_id,appointment_id),unique(clinic_id,created_by,operation),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id));
create function private.booklet_appointment(c uuid,p uuid,a uuid) returns text
language plpgsql stable security definer set search_path='' as $$declare s text;g uuid;begin
 if not private.booklet_access(c,false,false) then return null;end if;
 g=private.permission_effective(c,auth.uid(),'appointment.read');
 if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then return null;end if;
 select state into s from public.clinic_appointments where clinic_id=c and patient_id=p and id=a and kind='consulta'
  and (professional_id=auth.uid() or exists(select 1 from public.clinic_members where clinic_id=c and user_id=auth.uid() and role::text in ('admin','mvz','auxiliar','recepcion')));
 return s;
end$$;
revoke all on function private.booklet_appointment(uuid,uuid,uuid) from public,anon;
grant execute on function private.booklet_appointment(uuid,uuid,uuid) to authenticated;
create function private.booklet_audit() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(new.clinic_id,auth.uid(),'booklet_'||tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(new)->>'plan_id'));
 return new;
end$$;
revoke all on function private.booklet_audit() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['preventive_evidence','preventive_plans','preventive_plan_retirements','preventive_appointment_links'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create trigger booklet_immutable before update or delete on public.%I for each row execute function private.inv_history_guard()',t);
 execute format('create trigger booklet_audit after insert on public.%I for each row execute function private.booklet_audit()',t);
 end loop;
end$$;
grant insert(clinic_id,patient_id,event_id,label,mime,content,operation) on public.preventive_evidence to authenticated;
grant insert(clinic_id,patient_id,event_id,type,coverage,due_date,reason,operation) on public.preventive_plans to authenticated;
grant insert(plan_id,clinic_id,patient_id,reason,operation) on public.preventive_plan_retirements to authenticated;
grant insert(plan_id,appointment_id,clinic_id,patient_id,operation,request) on public.preventive_appointment_links to authenticated;
create policy evidence_read on public.preventive_evidence for select to authenticated using(private.booklet_access(clinic_id) and exists(
 select 1 from public.vet_patient_events e where e.id=event_id and e.clinic_id=preventive_evidence.clinic_id and e.patient_id=preventive_evidence.patient_id and e.kind='preventive'));
create policy evidence_write on public.preventive_evidence for insert to authenticated with check(created_by=auth.uid() and private.booklet_locked_access(clinic_id,true,false) and exists(
 select 1 from public.vet_patient_events e where e.id=event_id and e.clinic_id=preventive_evidence.clinic_id and e.patient_id=preventive_evidence.patient_id and e.kind='preventive'));
create policy plan_read on public.preventive_plans for select to authenticated using(private.booklet_access(clinic_id) and exists(
 select 1 from public.vet_patients p where p.id=patient_id and p.clinic_id=preventive_plans.clinic_id)
 and (event_id is null or exists(select 1 from public.vet_patient_events e where e.id=event_id and e.clinic_id=preventive_plans.clinic_id and e.patient_id=preventive_plans.patient_id and e.kind='preventive')));
create policy plan_write on public.preventive_plans for insert to authenticated with check(created_by=auth.uid() and private.booklet_locked_access(clinic_id,true,true) and exists(
 select 1 from public.vet_patients p where p.id=patient_id and p.clinic_id=preventive_plans.clinic_id)
 and (event_id is null or exists(select 1 from public.vet_patient_events e where e.id=event_id and e.clinic_id=preventive_plans.clinic_id and e.patient_id=preventive_plans.patient_id and e.kind='preventive')));
create policy retirement_read on public.preventive_plan_retirements for select to authenticated using(exists(select 1 from public.preventive_plans p where p.id=plan_id and p.clinic_id=preventive_plan_retirements.clinic_id and p.patient_id=preventive_plan_retirements.patient_id));
create policy retirement_write on public.preventive_plan_retirements for insert to authenticated with check(created_by=auth.uid() and private.booklet_locked_access(clinic_id,true,true) and exists(select 1 from public.preventive_plans p where p.id=plan_id and p.clinic_id=preventive_plan_retirements.clinic_id and p.patient_id=preventive_plan_retirements.patient_id));
create policy link_read on public.preventive_appointment_links for select to authenticated using(exists(select 1 from public.preventive_plans p where p.id=plan_id and p.clinic_id=preventive_appointment_links.clinic_id and p.patient_id=preventive_appointment_links.patient_id) and private.booklet_appointment(clinic_id,patient_id,appointment_id) is not null);
create policy link_write on public.preventive_appointment_links for insert to authenticated with check(created_by=auth.uid() and private.booklet_locked_access(clinic_id,false,false,true) and exists(select 1 from public.preventive_plans p where p.id=plan_id and p.clinic_id=preventive_appointment_links.clinic_id and p.patient_id=preventive_appointment_links.patient_id) and private.booklet_appointment(clinic_id,patient_id,appointment_id) is not null and private.booklet_appointment(clinic_id,patient_id,appointment_id)<>'cancelado');
-- A direct allowed INSERT must obey the same one-active-appointment invariant.
create function private.booklet_plan_lock() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if not private.booklet_locked_access(new.clinic_id,tg_table_name='preventive_plan_retirements',tg_table_name='preventive_plan_retirements',tg_table_name='preventive_appointment_links') then raise exception 'explicit_permission_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(new.plan_id::text,73));
 if tg_table_name='preventive_appointment_links' then
  if exists(select 1 from public.preventive_plan_retirements where plan_id=new.plan_id) then raise exception 'plan_retired';end if;
  if exists(select 1 from public.preventive_appointment_links where plan_id=new.plan_id and private.booklet_appointment(clinic_id,patient_id,appointment_id)<>'cancelado') then raise exception 'plan_already_scheduled';end if;
 end if;return new;
end$$;
revoke all on function private.booklet_plan_lock() from public,anon,authenticated;
create trigger booklet_plan_lock before insert on public.preventive_appointment_links for each row execute function private.booklet_plan_lock();
create trigger booklet_plan_lock before insert on public.preventive_plan_retirements for each row execute function private.booklet_plan_lock();
-- Reads and writes below run as the caller: existing event RLS remains in force.
create function public.preventive_booklet_snapshot(p_clinic uuid,p_patient uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$declare p public.vet_patients;begin
 if not private.booklet_access(p_clinic) then raise exception 'explicit_permission_required';end if;
 select * into p from public.vet_patients where clinic_id=p_clinic and id=p_patient;
 if not found then raise exception 'patient_unavailable';end if;
 return jsonb_build_object('schema_version',2,'clinic_id',p_clinic,'patient_id',p_patient,'patient_name',p.name,'species',p.species,
  'can_attach',private.booklet_access(p_clinic,true),'can_confirm',private.booklet_access(p_clinic,true,true),
  'can_schedule',private.booklet_schedule_access(p_clinic),
  'members',case when private.booklet_schedule_access(p_clinic) then coalesce(public.ops_dashboard(p_clinic)->'members','[]') else '[]'::jsonb end,
  'events',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]') from public.vet_patient_events e where e.clinic_id=p_clinic and e.patient_id=p_patient and e.kind='preventive'),
  'evidence',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'event_id',event_id,'label',label,'mime',mime,'size',octet_length(content),'created_at',created_at)),'[]') from public.preventive_evidence where clinic_id=p_clinic and patient_id=p_patient),
  'plans',(select coalesce(jsonb_agg(to_jsonb(x) order by due_date,id),'[]') from public.preventive_plans x where clinic_id=p_clinic and patient_id=p_patient),
  'retired',(select coalesce(jsonb_agg(plan_id),'[]') from public.preventive_plan_retirements where clinic_id=p_clinic and patient_id=p_patient),
  'links',(select coalesce(jsonb_agg(jsonb_build_object('plan_id',plan_id,'appointment_id',appointment_id,'state',private.booklet_appointment(clinic_id,patient_id,appointment_id))),'[]') from public.preventive_appointment_links where clinic_id=p_clinic and patient_id=p_patient));
end$$;
create function public.preventive_evidence_add(p_clinic uuid,p_patient uuid,p_event uuid,p_label text,p_mime text,p_content text,p_operation text)
returns uuid language plpgsql security invoker set search_path='' as $$declare r public.preventive_evidence;b bytea;begin
 if not private.booklet_locked_access(p_clinic,true,false) then raise exception 'explicit_permission_required';end if;
 if length(p_content)>4194304 or p_content is null then raise exception 'invalid_evidence';end if;
 b=decode(p_content,'base64');
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_clinic::text||p_operation,71));
 select * into r from public.preventive_evidence where clinic_id=p_clinic and created_by=auth.uid() and operation=p_operation;
 if found then
  if r.patient_id<>p_patient or r.event_id<>p_event or r.label<>p_label or r.mime<>p_mime or r.content<>b then raise exception 'operation_payload_changed';end if;return r.id;
 end if;
 insert into public.preventive_evidence(clinic_id,patient_id,event_id,label,mime,content,operation)
 values(p_clinic,p_patient,p_event,p_label,p_mime,b,p_operation) returning id into r.id;return r.id;
end$$;
create function public.preventive_evidence_get(p_clinic uuid,p_patient uuid,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$declare r public.preventive_evidence;begin
 if not private.booklet_access(p_clinic) then raise exception 'explicit_permission_required';end if;
 select * into r from public.preventive_evidence where clinic_id=p_clinic and patient_id=p_patient and id=p_id;
 if not found then raise exception 'evidence_unavailable';end if;
 return jsonb_build_object('mime',r.mime,'content',encode(r.content,'base64'));
end$$;
revoke all on function public.preventive_evidence_get(uuid,uuid,uuid) from public,anon;
grant execute on function public.preventive_evidence_get(uuid,uuid,uuid) to authenticated;
create function public.preventive_plan_add(p_clinic uuid,p_patient uuid,p_data jsonb,p_operation text)
returns uuid language plpgsql security invoker set search_path='' as $$declare r public.preventive_plans;e uuid;d date;begin
 if not private.booklet_locked_access(p_clinic,true,true) then raise exception 'professional_confirmation_required';end if;
 e=nullif(p_data->>'event_id','')::uuid;d=(p_data->>'due_date')::date;
 if jsonb_typeof(p_data)<>'object' or p_data->>'due_date' !~ '^\d{4}-\d{2}-\d{2}$' or d is null then raise exception 'invalid_plan';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_clinic::text||p_operation,72));
 select * into r from public.preventive_plans where clinic_id=p_clinic and created_by=auth.uid() and operation=p_operation;
 if found then
  if r.patient_id<>p_patient or r.event_id is distinct from e or r.type is distinct from p_data->>'type' or r.coverage is distinct from p_data->>'coverage' or r.due_date<>d or r.reason is distinct from p_data->>'reason' then raise exception 'operation_payload_changed';end if;return r.id;
 end if;
 insert into public.preventive_plans(clinic_id,patient_id,event_id,type,coverage,due_date,reason,operation)
 values(p_clinic,p_patient,e,p_data->>'type',p_data->>'coverage',d,p_data->>'reason',p_operation) returning id into r.id;return r.id;
end$$;
create function public.preventive_plan_retire(p_clinic uuid,p_patient uuid,p_plan uuid,p_reason text,p_operation text)
returns void language plpgsql security invoker set search_path='' as $$declare r public.preventive_plan_retirements;begin
 if not private.booklet_locked_access(p_clinic,true,true) then raise exception 'professional_confirmation_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_plan::text,73));
 select * into r from public.preventive_plan_retirements where plan_id=p_plan;
 if found then
  if r.clinic_id<>p_clinic or r.patient_id<>p_patient or r.reason<>p_reason or r.operation<>p_operation or r.created_by<>auth.uid() then raise exception 'plan_already_retired';end if;return;
 end if;
 insert into public.preventive_plan_retirements(plan_id,clinic_id,patient_id,reason,operation) values(p_plan,p_clinic,p_patient,p_reason,p_operation);
end$$;
create function public.preventive_plan_schedule(p_clinic uuid,p_patient uuid,p_plan uuid,p_data jsonb,p_operation text)
returns uuid language plpgsql security invoker set search_path='' as $$declare p public.preventive_plans;r public.preventive_appointment_links;a uuid;begin
 if not private.booklet_locked_access(p_clinic,false,false,true) then raise exception 'explicit_permission_required';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>10000 then raise exception 'invalid_appointment';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_plan::text,73));
 select * into p from public.preventive_plans where id=p_plan and clinic_id=p_clinic and patient_id=p_patient;
 if not found then raise exception 'plan_unavailable';end if;
 if exists(select 1 from public.preventive_plan_retirements where plan_id=p.id) then raise exception 'plan_retired';end if;
 select * into r from public.preventive_appointment_links where clinic_id=p_clinic and created_by=auth.uid() and operation=p_operation;
 if found then
  if r.plan_id<>p_plan or r.patient_id<>p_patient or r.request<>p_data then raise exception 'operation_payload_changed';end if;return r.appointment_id;
 end if;
 if exists(select 1 from public.preventive_appointment_links where plan_id=p.id and private.booklet_appointment(clinic_id,patient_id,appointment_id)<>'cancelado') then raise exception 'plan_already_scheduled';end if;
 a=public.ops_write(p_clinic,'appointment',jsonb_build_object('patient_id',p_patient,'kind','consulta',
  'professional_id',p_data->>'professional_id','starts_at',p_data->>'starts_at','ends_at',p_data->>'ends_at',
  'notes','Cita preventiva solicitada desde el carnet; confirmar aplicación con el MVZ.'),p_operation);
 insert into public.preventive_appointment_links(plan_id,appointment_id,clinic_id,patient_id,operation,request) values(p.id,a,p_clinic,p_patient,p_operation,p_data);
 return a;
end$$;
revoke all on function public.preventive_booklet_snapshot(uuid,uuid),public.preventive_evidence_add(uuid,uuid,uuid,text,text,text,text),public.preventive_plan_add(uuid,uuid,jsonb,text),public.preventive_plan_retire(uuid,uuid,uuid,text,text),public.preventive_plan_schedule(uuid,uuid,uuid,jsonb,text) from public,anon;
grant execute on function public.preventive_booklet_snapshot(uuid,uuid),public.preventive_evidence_add(uuid,uuid,uuid,text,text,text,text),public.preventive_plan_add(uuid,uuid,jsonb,text),public.preventive_plan_retire(uuid,uuid,uuid,text,text),public.preventive_plan_schedule(uuid,uuid,uuid,jsonb,text) to authenticated;
-- Structured coverage enriches an existing event; no product-name inference or event ACL change.
create function private.validate_preventive_coverage_v2() returns trigger language plpgsql set search_path='' as $$declare k text;begin
 if new.kind='preventive' and new.payload ? 'coverage_version' then
  if new.payload->'coverage_version' is distinct from '1'::jsonb or jsonb_typeof(new.payload->'coverage_components') is distinct from 'array' or jsonb_array_length(new.payload->'coverage_components')>14 or jsonb_typeof(new.payload->'coverage_other') is distinct from 'string' or length(new.payload->>'coverage_other')>500 then raise exception 'invalid_coverage';end if;
  for k in select jsonb_array_elements_text(new.payload->'coverage_components') loop
   if k not in ('rabies','canine_distemper','canine_parvovirus','canine_adenovirus','canine_parainfluenza','leptospirosis','bordetella','feline_panleukopenia','feline_herpesvirus','feline_calicivirus','feline_leukemia','feline_chlamydia','internal_parasites','external_parasites') then raise exception 'invalid_coverage';end if;
  end loop;
  if (select count(*)<>count(distinct v) from jsonb_array_elements_text(new.payload->'coverage_components') v) then raise exception 'invalid_coverage';end if;
 end if;return new;
end$$;
revoke all on function private.validate_preventive_coverage_v2() from public,anon,authenticated;
create trigger validate_preventive_coverage_v2 before insert on public.vet_patient_events for each row execute function private.validate_preventive_coverage_v2();
notify pgrst,'reload schema';
commit;
