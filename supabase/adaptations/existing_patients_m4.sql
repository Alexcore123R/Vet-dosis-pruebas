-- Apply once after M2. M3 is independent. No existing rows are changed.
begin;
create table public.vet_owners (
 id uuid primary key default gen_random_uuid(), clinic_id uuid not null references public.clinics(id),
 name text not null check(length(btrim(name)) between 1 and 200),
 phone text not null default '',email text not null default '',address text not null default '',
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(clinic_id,id)
);
create table public.vet_patients (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 name text not null check(length(btrim(name)) between 1 and 120),
 species text not null check(length(btrim(species)) between 1 and 120),breed text not null default '',
 sex text not null check(sex in ('hembra','macho','sin especificar')),birth_date date,
 owner_id uuid,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(clinic_id,id),foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id)
);
create table public.vet_patient_events (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,
 patient_id uuid not null,kind text not null check(kind in ('soap','weight','allergy','preventive','consent')),
 payload jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id)
);
create index vet_patients_clinic on public.vet_patients(clinic_id,name);
create index vet_events_patient on public.vet_patient_events(clinic_id,patient_id,created_at);
create table private.vet_operation_receipts (
 user_id uuid not null,clinic_id uuid not null,operation_id text not null,
 fingerprint jsonb not null,entity_id uuid not null,primary key(user_id,clinic_id,operation_id)
);
revoke all on public.vet_owners,public.vet_patients,public.vet_patient_events from public,anon,authenticated;
revoke all on private.vet_operation_receipts from public,anon,authenticated;
grant select on public.vet_owners,public.vet_patients,public.vet_patient_events to authenticated;
alter table public.vet_owners enable row level security;
alter table public.vet_patients enable row level security;
alter table public.vet_patient_events enable row level security;
create policy vet_owner_read on public.vet_owners for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','recepcion']));
create policy vet_patient_read on public.vet_patients for select to authenticated using(private.has_clinic_role(clinic_id,array['admin','mvz','auxiliar','recepcion','estilista']));
create policy vet_event_read on public.vet_patient_events for select to authenticated using(
 private.has_clinic_role(clinic_id,case when kind='consent' then array['admin','mvz'] else array['admin','mvz','auxiliar'] end)
);
create function private.vet_receipt(p_clinic uuid,p_operation text,p_fingerprint jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare receipt private.vet_operation_receipts;
begin
 if p_operation is null or p_operation !~ '^[a-f0-9]{48}$' then raise exception 'invalid_operation'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text||p_clinic::text||p_operation,0));
 select * into receipt from private.vet_operation_receipts where user_id=auth.uid() and clinic_id=p_clinic and operation_id=p_operation;
 if found then
  if receipt.fingerprint<>p_fingerprint then raise exception 'operation_payload_changed'; end if;
  return receipt.entity_id;
 end if;
 return null;
end $$;
revoke all on function private.vet_receipt(uuid,text,jsonb) from public,anon,authenticated;
create function public.create_vet_patient(p_clinic_id uuid,p_patient jsonb,p_owner jsonb,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;owner uuid;fingerprint jsonb;birth date;field text;
begin
 if not private.has_clinic_role(p_clinic_id,array['admin','mvz','recepcion']) then raise exception 'patient_role_required'; end if;
 fingerprint=jsonb_build_object('kind','patient','patient',p_patient,'owner',p_owner);
 v_id=private.vet_receipt(p_clinic_id,p_operation_id,fingerprint);if v_id is not null then return v_id;end if;
 if jsonb_typeof(p_patient) is distinct from 'object' then raise exception 'invalid_patient'; end if;
 foreach field in array array['name','species'] loop
  if jsonb_typeof(p_patient->field) is distinct from 'string' or length(btrim(p_patient->>field)) not between 1 and 120 then raise exception 'invalid_patient'; end if;
 end loop;
 if p_patient->>'sex' is null or p_patient->>'sex' not in ('hembra','macho','sin especificar') then raise exception 'invalid_sex';end if;
 if p_patient->>'birth_date' is not null and p_patient->>'birth_date'<>'' then
  if p_patient->>'birth_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_date';end if;
  birth=(p_patient->>'birth_date')::date;
  if birth>current_date then raise exception 'future_birth_date';end if;
 end if;
 if length(coalesce(p_patient->>'breed',''))>120 then raise exception 'invalid_breed';end if;
 if p_owner is not null and p_owner<>'null'::jsonb then
  if p_patient->>'owner_id' is not null then raise exception 'duplicate_owner_input';end if;
  if jsonb_typeof(p_owner) is distinct from 'object' or jsonb_typeof(p_owner->'name') is distinct from 'string' or length(btrim(p_owner->>'name')) not between 1 and 200 then raise exception 'invalid_owner';end if;
  foreach field in array array['phone','email','address'] loop
   if p_owner->field is not null and p_owner->field<>'null'::jsonb and jsonb_typeof(p_owner->field)<>'string' then raise exception 'invalid_owner';end if;
   if length(coalesce(p_owner->>field,''))>1000 then raise exception 'invalid_owner';end if;
  end loop;
  insert into public.vet_owners(clinic_id,name,phone,email,address,created_by)
  values(p_clinic_id,btrim(p_owner->>'name'),coalesce(p_owner->>'phone',''),coalesce(p_owner->>'email',''),coalesce(p_owner->>'address',''),auth.uid()) returning id into owner;
  insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'owner_created',owner);
 elsif p_patient->>'owner_id' is not null then
  owner=(p_patient->>'owner_id')::uuid;
  if not exists(select 1 from public.vet_owners where clinic_id=p_clinic_id and id=owner) then raise exception 'owner_wrong_clinic';end if;
 end if;
 insert into public.vet_patients(clinic_id,name,species,breed,sex,birth_date,owner_id,created_by)
 values(p_clinic_id,btrim(p_patient->>'name'),btrim(p_patient->>'species'),coalesce(p_patient->>'breed',''),p_patient->>'sex',birth,owner,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fingerprint,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic_id,auth.uid(),'patient_created',v_id);
 return v_id;
end $$;
create function public.add_vet_patient_event(p_clinic_id uuid,p_patient_id uuid,p_kind text,p_payload jsonb,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fingerprint jsonb;field text;v_date date;point jsonb;points integer=0;first_x numeric;first_y numeric;moved boolean=false;x numeric;y numeric;
begin
 if p_kind is null or p_kind not in ('soap','weight','allergy','preventive','consent') then raise exception 'invalid_event_kind';end if;
 if not private.has_clinic_role(p_clinic_id,case when p_kind in ('soap','consent') then array['admin','mvz'] else array['admin','mvz','auxiliar'] end) then raise exception 'clinical_role_required';end if;
 if not exists(select 1 from public.vet_patients where clinic_id=p_clinic_id and id=p_patient_id) then raise exception 'patient_wrong_clinic';end if;
 fingerprint=jsonb_build_object('kind',p_kind,'patient',p_patient_id,'payload',p_payload);
 v_id=private.vet_receipt(p_clinic_id,p_operation_id,fingerprint);if v_id is not null then return v_id;end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or pg_catalog.octet_length(p_payload::text)>400000 then raise exception 'invalid_payload';end if;
 if jsonb_typeof(p_payload->'date') is distinct from 'string' or p_payload->>'date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_date';end if;
 v_date=(p_payload->>'date')::date;
 if p_kind='soap' then
  foreach field in array array['reason','species_template'] loop
   if jsonb_typeof(p_payload->field) is distinct from 'string' or length(btrim(p_payload->>field)) not between 1 and 300 then raise exception 'invalid_soap';end if;
  end loop;
  foreach field in array array['subjective','objective','assessment','plan'] loop
   if jsonb_typeof(p_payload->field) is distinct from 'string' or length(p_payload->>field)>4000 then raise exception 'invalid_soap';end if;
  end loop;
  if concat(btrim(p_payload->>'subjective'),btrim(p_payload->>'objective'),btrim(p_payload->>'assessment'),btrim(p_payload->>'plan'))='' then raise exception 'empty_soap';end if;
 elsif p_kind='weight' then
  if jsonb_typeof(p_payload->'kg') is distinct from 'string' or p_payload->>'kg' !~ '^\d{1,12}(\.\d{1,9})?$' then raise exception 'invalid_weight';end if;
  if (p_payload->>'kg')::numeric<=0 then raise exception 'invalid_weight';end if;
 elsif p_kind='allergy' then
  if jsonb_typeof(p_payload->'substance') is distinct from 'string' or length(btrim(p_payload->>'substance')) not between 1 and 300 or jsonb_typeof(p_payload->'reaction') is distinct from 'string' or length(btrim(p_payload->>'reaction')) not between 1 and 4000 then raise exception 'invalid_allergy';end if;
 elsif p_kind='preventive' then
  if p_payload->>'type' is null or p_payload->>'type' not in ('vacuna','desparasitación') or jsonb_typeof(p_payload->'product') is distinct from 'string' or length(btrim(p_payload->>'product')) not between 1 and 300 then raise exception 'invalid_preventive';end if;
  if p_payload->>'next_date' is not null then
   if p_payload->>'next_date' !~ '^\d{4}-\d{2}-\d{2}$' or (p_payload->>'next_date')::date<v_date then raise exception 'invalid_next_date';end if;
  end if;
 elsif p_kind='consent' then
  foreach field in array array['procedure','signer','text'] loop
   if jsonb_typeof(p_payload->field) is distinct from 'string' or btrim(p_payload->>field)='' then raise exception 'invalid_consent';end if;
  end loop;
  if length(p_payload->>'procedure')>300 or length(p_payload->>'signer')>300 or length(p_payload->>'text')>20000 then raise exception 'invalid_consent';end if;
  if p_payload->'accepted' is distinct from 'true'::jsonb or jsonb_typeof(p_payload->'signature') is distinct from 'array' then raise exception 'consent_not_signed';end if;
  if jsonb_array_length(p_payload->'signature') not between 2 and 5000 then raise exception 'consent_not_signed';end if;
  for point in select * from jsonb_array_elements(p_payload->'signature') loop
   if point='null'::jsonb then continue;end if;
   if jsonb_typeof(point) is distinct from 'array' then raise exception 'invalid_signature';end if;
   if jsonb_array_length(point)<>2 or jsonb_typeof(point->0) is distinct from 'number' or jsonb_typeof(point->1) is distinct from 'number' then raise exception 'invalid_signature';end if;
   x=(point->>0)::numeric;y=(point->>1)::numeric;
   if x<0 or x>1 or y<0 or y>1 then raise exception 'invalid_signature';end if;
   if first_x is null then first_x=x;first_y=y;end if;
   if abs(x-first_x)+abs(y-first_y)>0.005 then moved=true;end if;points=points+1;
  end loop;
  if points<2 or not moved then raise exception 'consent_not_signed';end if;
 end if;
 insert into public.vet_patient_events(clinic_id,patient_id,kind,payload,created_by) values(p_clinic_id,p_patient_id,p_kind,p_payload,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic_id,p_operation_id,fingerprint,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic_id,auth.uid(),'patient_event_created',v_id,jsonb_build_object('kind',p_kind,'patient_id',p_patient_id));
 return v_id;
end $$;
revoke all on function public.create_vet_patient(uuid,jsonb,jsonb,text),public.add_vet_patient_event(uuid,uuid,text,jsonb,text) from public,anon;
grant execute on function public.create_vet_patient(uuid,jsonb,jsonb,text),public.add_vet_patient_event(uuid,uuid,text,jsonb,text) to authenticated;
commit;
