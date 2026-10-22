-- Isolated new-endpoint regression fixture; not proof of the full remote RLS cutover.
create schema private;create schema auth;
create table private.beta_policy(admissions_enabled boolean,enforcement_enabled boolean);
insert into private.beta_policy values(false,false);
create table private.permission_policy(enforcement_enabled boolean);
insert into private.permission_policy values(false);
do $$begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
end$$;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.clinics(id uuid primary key);
create table public.clinic_members(clinic_id uuid,user_id uuid,role text default 'admin',created_at timestamptz default now(),primary key(clinic_id,user_id));
create table private.member_permission_grants(id uuid primary key default gen_random_uuid(),clinic_id uuid,user_id uuid,code text,valid_until timestamptz);
create function private.permission_effective(c uuid,u uuid,k text) returns uuid language sql stable as $$
 select id from private.member_permission_grants g where clinic_id=c and user_id=u and code=k and valid_until>statement_timestamp()
 and exists(select 1 from public.clinic_members m where m.clinic_id=c and m.user_id=u) limit 1$$;
create function private.permission_require(c uuid,k text) returns uuid language plpgsql as $$declare g uuid;begin
 g=private.permission_effective(c,auth.uid(),k);if g is null then raise exception 'explicit_permission_required';end if;return g;end$$;
create table public.vet_owners(id uuid primary key,clinic_id uuid,name text,phone text default '',email text default '',address text default '',
 created_by uuid,created_at timestamptz default now(),unique(clinic_id,id));
create table public.vet_patients(id uuid primary key,clinic_id uuid,owner_id uuid,name text default 'Synthetic patient',species text default 'Canino',unique(clinic_id,id));
create table public.audit_log(clinic_id uuid,actor_id uuid,action text,entity_id text,details jsonb);
create table private.vet_operation_receipts(user_id uuid,clinic_id uuid,operation_id text,fingerprint jsonb,entity_id uuid,primary key(user_id,clinic_id,operation_id));
create function private.vet_receipt(c uuid,op text,fp jsonb) returns uuid language plpgsql as $$declare r private.vet_operation_receipts;begin
 if op !~ '^[a-f0-9]{48}$' then raise exception 'invalid_operation';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||c::text||op,0));
 select * into r from private.vet_operation_receipts where user_id=auth.uid() and clinic_id=c and operation_id=op;
 if found then if r.fingerprint<>fp then raise exception 'operation_payload_changed';end if;return r.entity_id;end if;return null;end$$;
create function private.inv_history_guard() returns trigger language plpgsql as $$begin raise exception 'immutable_history';end$$;

create table public.clinic_appointments(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),patient_id uuid,patient_name text not null,species text not null,kind text not null check(kind in ('consulta','estetica')),professional_id uuid not null,starts_at timestamptz not null,ends_at timestamptz not null,state text not null default 'agendado' check(state in ('agendado','en_atencion','listo','entregado','cancelado')),notes text not null default '' check(length(notes)<=2000),version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,professional_id) references public.clinic_members(clinic_id,user_id),check(ends_at>starts_at and ends_at<=starts_at+interval '24 hours'));
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
create function public.ops_write(c uuid,a text,d jsonb,op text) returns uuid language sql security definer as $$select private.permission_appointment_write(c,a,d,op)$$;
create function public.ops_dashboard(c uuid) returns jsonb language sql security definer as $$select jsonb_build_object('members',jsonb_build_array(jsonb_build_object('user_id',auth.uid(),'display_name','Synthetic MVZ')))$$;
create table public.vet_patient_events(id uuid primary key default gen_random_uuid(),clinic_id uuid,patient_id uuid,kind text,payload jsonb,
 created_by uuid default auth.uid(),created_at timestamptz default now(),hidden boolean default false);
create table private.synthetic_verification(user_id uuid primary key,verified boolean default true);
create function private.clinical_professional_at(c uuid,u uuid,t timestamptz) returns boolean language sql stable security definer as $$select verified from private.synthetic_verification where user_id=u$$;
\ir ../adaptations/preventive_booklet_v2.sql
grant usage on schema private,auth to authenticated;
grant select on public.vet_patients,public.vet_patient_events to authenticated;
alter table public.vet_patients enable row level security;
alter table public.vet_patient_events enable row level security;
create policy synthetic_patient_read on public.vet_patients for select to authenticated using(private.booklet_access(clinic_id));
create policy synthetic_event_read on public.vet_patient_events for select to authenticated using(private.booklet_access(clinic_id) and not hidden);
insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.clinics values('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002');
insert into public.clinic_members(clinic_id,user_id,role) select id,auth.uid(),'mvz' from public.clinics;
insert into private.synthetic_verification values(auth.uid(),true);
insert into private.member_permission_grants(clinic_id,user_id,code,valid_until)
 select '10000000-0000-0000-0000-000000000001',auth.uid(),x,now()+interval '1 day'
 from unnest(array['patient.read','patient.write','clinical.read','clinical.authorize','appointment.read','appointment.manage']) x;
insert into public.vet_patients(id,clinic_id) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002');
insert into public.vet_patient_events(id,clinic_id,patient_id,kind,payload,hidden) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','preventive','{"date":"2026-10-20","type":"vacuna","coverage":"Rabia"}',false),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','preventive','{"date":"2026-10-20","type":"vacuna","coverage":"Hidden"}',true),
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','preventive','{}',false);
-- Assertions run under authenticated, including real caller RLS and column grants.
set role authenticated;
do $$declare c uuid='10000000-0000-0000-0000-000000000001';p uuid='30000000-0000-0000-0000-000000000001';
 e uuid='40000000-0000-0000-0000-000000000001';att uuid;plan uuid;appt uuid;d jsonb;r jsonb;begin
 r=public.preventive_booklet_snapshot(c,p);
 if jsonb_array_length(r->'events')<>1 or r->'can_confirm'<>'true'::jsonb then raise exception 'snapshot_failed';end if;
 att=public.preventive_evidence_add(c,p,e,'Synthetic proof','application/pdf',encode(convert_to('%PDF-1.4 Synthetic','UTF8'),'base64'),repeat('a',48));
 if att<>public.preventive_evidence_add(c,p,e,'Synthetic proof','application/pdf',encode(convert_to('%PDF-1.4 Synthetic','UTF8'),'base64'),repeat('a',48)) then raise exception 'duplicate_attachment';end if;
 r=public.preventive_evidence_get(c,p,att);
 if r->>'mime'<>'application/pdf' then raise exception 'missing_attachment';end if;
 begin
  perform public.preventive_evidence_add(c,p,'40000000-0000-0000-0000-000000000002','Hidden','application/pdf',encode(convert_to('%PDF-1.4','UTF8'),'base64'),repeat('b',48));
  raise exception 'expected_denial';
 exception when insufficient_privilege then null;end;
 d='{"event_id":"40000000-0000-0000-0000-000000000001","type":"vacuna","coverage":"Rabia","due_date":"2030-01-01","reason":"Synthetic manual recommendation"}';
 plan=public.preventive_plan_add(c,p,d,repeat('c',48));
 if plan<>public.preventive_plan_add(c,p,d,repeat('c',48)) then raise exception 'duplicate_plan';end if;
 d=jsonb_build_object('professional_id',auth.uid(),'starts_at','2030-01-01T10:00:00Z','ends_at','2030-01-01T11:00:00Z');
 appt=public.preventive_plan_schedule(c,p,plan,d,repeat('d',48));
 if appt<>public.preventive_plan_schedule(c,p,plan,d,repeat('d',48)) then raise exception 'duplicate_appointment';end if;
 begin
  perform public.preventive_plan_schedule(c,p,plan,d,repeat('e',48));raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>'plan_already_scheduled' then raise;end if;end;
 perform public.preventive_plan_retire(c,p,plan,'Synthetic correction',repeat('f',48));
 perform public.preventive_plan_retire(c,p,plan,'Synthetic correction',repeat('f',48));
 begin
  perform public.preventive_plan_schedule(c,p,plan,d,repeat('1',48));raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>'plan_retired' then raise;end if;end;
 r=public.preventive_booklet_snapshot(c,p);
 if jsonb_array_length(r->'plans')<>1 or jsonb_array_length(r->'retired')<>1 or jsonb_array_length(r->'links')<>1 then raise exception 'history_lost';end if;
 begin
  perform public.preventive_booklet_snapshot(c,'30000000-0000-0000-0000-000000000002');raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>'patient_unavailable' then raise;end if;end;
end$$;
reset role;
-- Revoked source visibility hides its attachments/plans without rewriting their history.
update public.vet_patient_events set hidden=true where id='40000000-0000-0000-0000-000000000001';
set role authenticated;
do $$declare r jsonb;begin
 r=public.preventive_booklet_snapshot('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');
 if jsonb_array_length(r->'events')<>0 or jsonb_array_length(r->'evidence')<>0 or jsonb_array_length(r->'plans')<>0 then raise exception 'hidden_source_leak';end if;
end$$;
reset role;
update private.synthetic_verification set verified=false;
set role authenticated;
do $$begin
 begin
  perform public.preventive_plan_add('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','{"type":"vacuna","coverage":"Test","due_date":"2030-01-01","reason":"Test"}',repeat('2',48));raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>'professional_confirmation_required' then raise;end if;end;
end$$;
reset role;
delete from private.member_permission_grants where code='clinical.read';
set role authenticated;
do $$begin
 begin
  perform public.preventive_booklet_snapshot('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>'explicit_permission_required' then raise;end if;end;
 if exists(select 1 from public.preventive_evidence) then raise exception 'direct_read_leak';end if;
end$$;
reset role;
do $$begin
 if has_table_privilege('anon','public.preventive_evidence','select') or
 has_table_privilege('authenticated','public.preventive_evidence','update') or
 has_column_privilege('authenticated','public.preventive_plans','created_by','insert') or
 has_function_privilege('anon','public.preventive_booklet_snapshot(uuid,uuid)','execute') then raise exception 'grant_leak';end if;
 if (select count(*) from public.clinic_appointments)<>1 then raise exception 'appointment_duplicated_or_deleted';end if;
end$$;
