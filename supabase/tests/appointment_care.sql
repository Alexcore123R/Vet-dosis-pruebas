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
create table public.vet_patients(id uuid primary key,clinic_id uuid,owner_id uuid,unique(clinic_id,id));
create table public.audit_log(clinic_id uuid,actor_id uuid,action text,entity_id text);
create table private.vet_operation_receipts(user_id uuid,clinic_id uuid,operation_id text,fingerprint jsonb,entity_id uuid,primary key(user_id,clinic_id,operation_id));
create function private.vet_receipt(c uuid,op text,fp jsonb) returns uuid language plpgsql as $$declare r private.vet_operation_receipts;begin
 if op !~ '^[a-f0-9]{48}$' then raise exception 'invalid_operation';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||c::text||op,0));
 select * into r from private.vet_operation_receipts where user_id=auth.uid() and clinic_id=c and operation_id=op;
 if found then if r.fingerprint<>fp then raise exception 'operation_payload_changed';end if;return r.entity_id;end if;return null;end$$;
create function private.inv_history_guard() returns trigger language plpgsql as $$begin raise exception 'immutable_history';end$$;
create table public.clinic_appointments(id uuid primary key,clinic_id uuid,patient_id uuid,
 state text default 'agendado',version integer default 1,kind text default 'consulta',
 professional_id uuid,species text default 'canino');
create table public.clinic_service_acts(id uuid primary key,clinic_id uuid,appointment_id uuid,price numeric(18,2));
create table public.inventory_sales(id uuid primary key,clinic_id uuid);
create table public.inventory_sale_lines(sale_id uuid,clinic_id uuid,service_act_id uuid,total numeric(18,2),kind text default 'servicio');
create table public.inventory_sale_reversals(sale_id uuid,clinic_id uuid);
-- Synthetic dependencies: tests the new transaction, not the full installed cutover.
create table public.inventory_clinic_settings(clinic_id uuid,timezone text);
create table public.vet_patient_events(id uuid primary key default gen_random_uuid(),clinic_id uuid,patient_id uuid,kind text,payload jsonb);
create function public.ops_write(c uuid,action text,data jsonb,op text) returns uuid language plpgsql as $$
declare a public.clinic_appointments;begin
 perform private.permission_require(c,'appointment.manage');
 select * into a from public.clinic_appointments where clinic_id=c and id=(data->>'id')::uuid for update;
 if a.version is distinct from (data->>'version')::int then raise exception 'version_conflict';end if;
 if not ((a.state='agendado' and data->>'state'='en_atencion') or
  (a.state='en_atencion' and data->>'state'='listo') or (a.state='listo' and data->>'state'='entregado')) then raise exception 'invalid_transition';end if;
 update public.clinic_appointments set state=data->>'state',version=version+1 where id=a.id;return a.id;
end$$;
create function public.add_vet_patient_event(c uuid,p uuid,k text,d jsonb,op text) returns uuid language plpgsql as $$declare e uuid;begin
 perform private.permission_require(c,'patient.write');
 insert into public.vet_patient_events(clinic_id,patient_id,kind,payload) values(c,p,k,d) returning id into e;return e;
end$$;
\ir ../adaptations/appointment_care_v1.sql
insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.clinics values('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002');
insert into public.clinic_members(clinic_id,user_id,role) values('10000000-0000-0000-0000-000000000001',auth.uid(),'mvz');
insert into public.inventory_clinic_settings values('10000000-0000-0000-0000-000000000001','America/Mexico_City');
insert into private.member_permission_grants(clinic_id,user_id,code,valid_until)
 select '10000000-0000-0000-0000-000000000001',auth.uid(),x,clock_timestamp()+interval '1 day'
 from unnest(array['patient.read','patient.write','appointment.read','appointment.manage']) x;
insert into public.vet_patients values('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',null);
insert into public.clinic_appointments(id,clinic_id,patient_id,professional_id) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',auth.uid()),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',null,auth.uid());
create function public.test_care_denied(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>expected then raise exception 'Expected %, got %',expected,sqlerrm;end if;end;
end$$;
set role authenticated;
select public.appointment_care_snapshot('10000000-0000-0000-0000-000000000001',array['40000000-0000-0000-0000-000000000001'::uuid]);
reset role;
do $$declare c uuid='10000000-0000-0000-0000-000000000001';a uuid='40000000-0000-0000-0000-000000000001';x uuid;y uuid;d jsonb;r jsonb;begin
 d='{"reason":"Synthetic visit","belongings":"Collar","authorized_services":"Consulta","authorized_by":"Tutor","pickup_person":"Tutor","budget_accepted":true,"budget_reference":"Quote 1"}';
 x=public.appointment_care_write(c,a,1,'admit',d,repeat('a',48));
 y=public.appointment_care_write(c,a,1,'admit',d,repeat('a',48));
 if x<>y or (select version from public.clinic_appointments where id=a)<>2 then raise exception 'retry_failed';end if;
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,1,''ready'',%L,%L)',c,a,'{"instructions":"Test"}',repeat('b',48)),'version_conflict');
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,2,''deliver'',%L,%L)',c,a,'{}',repeat('b',48)),'invalid_transition');
 d=jsonb_build_object('instructions','Synthetic instruction','treatment','Synthetic treatment','followup','MVZ review','clinical_date',(clock_timestamp() at time zone 'America/Mexico_City')::date::text);
 x=public.appointment_care_write(c,a,2,'ready',d,repeat('c',48));
 y=public.appointment_care_write(c,a,2,'ready',d,repeat('c',48));
 if x<>y or (select count(*) from public.vet_patient_events)<>1 then raise exception 'clinical_duplicate';end if;
 if (select payload->>'reason'<>'Synthetic visit' from public.vet_patient_events limit 1) then raise exception 'clinical_reason_missing';end if;
 if (select payload->>'plan' not like '%Synthetic treatment%' from public.vet_patient_events limit 1) then raise exception 'clinical_plan_missing';end if;
 r=public.appointment_care_snapshot(c,array[a]);
 if r::text like '%Synthetic treatment%' or r::text like '%Synthetic instruction%' then raise exception 'clinical_leak';end if;
 if r->>'timezone'<>'America/Mexico_City' or (r->>'day_end')::timestamptz<=(r->>'day_start')::timestamptz then raise exception 'clinic_day_invalid';end if;
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,3,''deliver'',%L,%L)',c,a,
  '{"released_to":"Other","belongings_outcome":"Returned","pickup_verified":true,"instructions_delivered":true}',repeat('d',48)),'care_pickup_authorization_required');
 d='{"released_to":"Other","pickup_authorization":"Tutor confirmed pickup authorization","belongings_outcome":"Collar returned","pickup_verified":true,"instructions_delivered":true}';
 x=public.appointment_care_write(c,a,3,'deliver',d,repeat('e',48));
 y=public.appointment_care_write(c,a,3,'deliver',d,repeat('e',48));
 if x<>y or (select state from public.clinic_appointments where id=a)<>'entregado' or
 (select count(*) from public.appointment_care_records where appointment_id=a)<>3 then raise exception 'delivery_failed';end if;
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,4,''admit'',%L,%L)',c,'40000000-0000-0000-0000-000000000002','{}',repeat('f',48)),'access_denied');
end$$;
-- Operational staff can close grooming, but cannot write a medical discharge.
update public.clinic_members set role='recepcion';
insert into public.clinic_appointments(id,clinic_id,patient_id,professional_id,state,kind) values
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',null,auth.uid(),'en_atencion','estetica'),
 ('40000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',auth.uid(),'en_atencion','consulta');
do $$declare c uuid='10000000-0000-0000-0000-000000000001';a uuid='40000000-0000-0000-0000-000000000003';r jsonb;begin
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,1,''ready'',%L,%L)',c,
  '40000000-0000-0000-0000-000000000004','{"instructions":"Test"}',repeat('1',48)),'clinical_role_required');
 perform public.appointment_care_write(c,a,1,'ready','{"instructions":"Synthetic grooming instructions","followup":"Revision"}',repeat('2',48));
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,2,''ready'',%L,%L)',c,a,
  '{"instructions":"Changed"}',repeat('3',48)),'care_already_recorded');
 perform public.test_care_denied(format('select public.appointment_care_write(%L,%L,2,''deliver'',%L,%L)',c,a,
  '{"released_to":"Tutor","belongings_outcome":"None","pickup_verified":true,"instructions_delivered":true}',repeat('4',48)),'care_pickup_authorization_required');
 r=public.appointment_care_snapshot(c,array['40000000-0000-0000-0000-000000000004'::uuid]);
 if r->'appointments'->0->'can_close'<>'false'::jsonb then raise exception 'clinical_button_leak';end if;
 if (select count(*) from public.vet_patient_events)<>1 then raise exception 'extra_clinical_event';end if;
end$$;
-- Permission revocation prevents both fresh reads and receipt replays.
delete from private.member_permission_grants where code='appointment.manage';
select public.test_care_denied($q$select public.appointment_care_write('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',3,'deliver','{"released_to":"Other","pickup_authorization":"Tutor confirmed pickup authorization","belongings_outcome":"Collar returned","pickup_verified":true,"instructions_delivered":true}',repeat('e',48))$q$,'explicit_permission_required');
delete from private.member_permission_grants where code='appointment.read';
select public.test_care_denied($q$select public.appointment_care_snapshot('10000000-0000-0000-0000-000000000001',array[]::uuid[])$q$,'explicit_permission_required');
select public.test_care_denied('update public.appointment_care_records set details=''{}''','immutable_history');
do $$begin
 if has_table_privilege('authenticated','public.appointment_care_records','select') or
  has_table_privilege('authenticated','public.appointment_care_records','insert') or
  has_function_privilege('anon','public.appointment_care_snapshot(uuid,uuid[])','execute') or
  has_function_privilege('authenticated','private.appointment_care_guard(uuid,boolean)','execute') then raise exception 'privileges_leak';end if;
end$$;
