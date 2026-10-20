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
create table public.clinic_appointments(id uuid primary key,clinic_id uuid,patient_id uuid);
create table public.clinic_service_acts(id uuid primary key,clinic_id uuid,appointment_id uuid,price numeric(18,2));
create table public.inventory_sales(id uuid primary key,clinic_id uuid);
create table public.inventory_sale_lines(sale_id uuid,clinic_id uuid,service_act_id uuid,total numeric(18,2),kind text default 'servicio');
create table public.inventory_sale_reversals(sale_id uuid,clinic_id uuid);
\ir ../adaptations/patient_contacts_appointment_links_v1.sql
insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.clinics values('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002');
insert into public.clinic_members(clinic_id,user_id) select id,auth.uid() from public.clinics;
insert into private.member_permission_grants(clinic_id,user_id,code,valid_until)
 select '10000000-0000-0000-0000-000000000001',auth.uid(),x,now()+interval '1 day'
 from unnest(array['patient.read','patient.write','appointment.read','sales.read','inventory.read']) x;
insert into public.vet_owners(id,clinic_id,name,phone,address) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Synthetic','+520000000001','Original'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Other clinic','+520000000002','Other');
insert into public.vet_patients values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002');
insert into public.clinic_appointments values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002');
insert into public.clinic_service_acts values
 ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',100),
 ('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',50);
insert into public.inventory_sales values ('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
insert into public.inventory_sale_lines(sale_id,clinic_id,service_act_id,total) values ('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',100);
set role authenticated;
do $$declare c uuid='10000000-0000-0000-0000-000000000001';p uuid='30000000-0000-0000-0000-000000000001';
 o uuid='20000000-0000-0000-0000-000000000001';r jsonb;x uuid;y uuid;d jsonb;
begin
 r=public.patient_contact_snapshot(c,p);
 if r->'owner'->>'phone'<>'+520000000001' then raise exception 'phone_missing';end if;
 d='{"name":"Synthetic","phone":"+520000000003","phone_alt":"","email":"","address":"Updated","contact_name":"Authorized","contact_phone":"+520000000004","contact_relationship":"Family","contact_authorized":true}';
 x=public.patient_contact_save(c,p,o,1,d,repeat('a',48));
 y=public.patient_contact_save(c,p,o,1,d,repeat('a',48));
 if x<>y then raise exception 'retry_duplicate';end if;
 r=public.patient_contact_snapshot(c,p);
 if r->'owner'->>'contact_version'<>'2' then raise exception 'version_mismatch';end if;
 begin
  perform public.patient_contact_save(c,p,o,1,d,repeat('b',48));raise exception 'expected_conflict';
 exception when raise_exception then if sqlerrm<>'contact_version_conflict' then raise;end if;end;
 begin
  perform public.patient_contact_snapshot(c,'30000000-0000-0000-0000-000000000002');raise exception 'expected_clinic_denial';
 exception when raise_exception then if sqlerrm<>'patient_unavailable' then raise;end if;end;
 d=jsonb_build_object('recipient','Synthetic','method','llamada','outcome','sin_respuesta','occurred_at',now()-interval '1 minute','notes','Synthetic attempt, not abandonment');
 x=public.patient_contact_log(c,p,o,d,repeat('c',48));
 y=public.patient_contact_log(c,p,o,d,repeat('c',48));
 if x<>y then raise exception 'attempt_retry_duplicate';end if;
 r=public.patient_contact_snapshot(c,p);
 if jsonb_array_length(r->'attempts')<>1 then raise exception 'missing_attempt';end if;
 r=public.appointment_patient_links(c,array['40000000-0000-0000-0000-000000000001'::uuid,'40000000-0000-0000-0000-000000000003'::uuid]);
 if jsonb_array_length(r->'appointments')<>1 then raise exception 'other_clinic_appointment';end if;
 if r->'appointments'->0->'billing'->>'state'<>'partial' or r->'appointments'->0->'billing'->>'paid'<>'100.00' then raise exception 'wrong_partial';end if;
 if r->'appointments'->0->'contact'->>'phone'<>'+520000000003' then raise exception 'stale_agenda_contact';end if;
 r=public.appointment_patient_links(c,array['40000000-0000-0000-0000-000000000002'::uuid]);
 if r->'appointments'->0->'billing'->>'state'<>'no_charge' then raise exception 'invented_debt';end if;
end$$;
reset role;
-- A reversed POS receipt is not an active payment.
insert into public.inventory_sale_reversals values('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
set role authenticated;
do $$declare r jsonb;begin
 r=public.appointment_patient_links('10000000-0000-0000-0000-000000000001',array['40000000-0000-0000-0000-000000000001'::uuid]);
 if r->'appointments'->0->'billing'->>'state'<>'unpaid' then raise exception 'reversal_ignored';end if;
end$$;
reset role;
delete from private.member_permission_grants where code in ('patient.read','sales.read');
set role authenticated;
do $$declare r jsonb;begin
 r=public.appointment_patient_links('10000000-0000-0000-0000-000000000001',array['40000000-0000-0000-0000-000000000001'::uuid]);
 if r->'appointments'->0->'contact'<>'null'::jsonb or r->'appointments'->0->'billing'<>'null'::jsonb then raise exception 'revoked_data_leak';end if;
 begin
  perform public.patient_contact_snapshot('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');raise exception 'expected_denial';
 exception when raise_exception then if sqlerrm<>'explicit_permission_required' then raise;end if;end;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.patient_contact_snapshot(uuid,uuid)','execute') or
    has_function_privilege('authenticated','private.patient_contact_guard(uuid,boolean)','execute') then raise exception 'private_or_anon_access';end if;
 begin
  update public.patient_contact_attempts set notes='Mutated';raise exception 'expected_immutable';
 exception when raise_exception then if sqlerrm<>'immutable_history' then raise;end if;end;
end$$;
