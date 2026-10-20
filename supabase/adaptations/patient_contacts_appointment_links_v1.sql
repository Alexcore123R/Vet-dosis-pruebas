-- NEW additive patch; review against the test project's installed schema.
-- Requires M4/M8/M9, service-linked sale lines and explicit permission foundation.
-- Never rerun historical 01-08 scripts. No permission grants or admission changes.
begin;
do $$begin
 if (select not admissions_enabled and not enforcement_enabled from private.beta_policy) is distinct from true
    or (select enforcement_enabled from private.permission_policy) is distinct from false then
   raise exception 'closed_beta_and_dormant_permissions_required';
 end if;
end$$;
alter table public.vet_owners
 add column phone_alt text not null default '' check(length(phone_alt)<=300),
 add column contact_name text not null default '' check(length(contact_name)<=300),
 add column contact_phone text not null default '' check(length(contact_phone)<=300),
 add column contact_relationship text not null default '' check(length(contact_relationship)<=300),
 add column contact_authorized boolean not null default false,
 add column contact_version integer not null default 1;
create table private.owner_contact_revisions(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,owner_id uuid not null,
 version integer not null,previous_data jsonb not null,new_data jsonb not null,
 recorded_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id),unique(owner_id,version));
create table public.patient_contact_attempts(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,patient_id uuid not null,owner_id uuid not null,
 recipient text not null check(length(btrim(recipient)) between 1 and 300),
 method text not null check(method in ('llamada','whatsapp','presencial','otro')),
 outcome text not null check(outcome in ('contactado','sin_respuesta','no_disponible','otro')),
 occurred_at timestamptz not null,notes text not null default '' check(length(notes)<=1000),
 recorded_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,patient_id) references public.vet_patients(clinic_id,id),
 foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id));
alter table private.owner_contact_revisions enable row level security;
alter table public.patient_contact_attempts enable row level security;
revoke all on private.owner_contact_revisions,public.patient_contact_attempts from public,anon,authenticated;
create trigger owner_contact_revisions_immutable before update or delete on private.owner_contact_revisions
 for each row execute function private.inv_history_guard();
create trigger patient_contact_attempts_immutable before update or delete on public.patient_contact_attempts
 for each row execute function private.inv_history_guard();
create function private.patient_contact_guard(p_clinic uuid,p_write boolean)
returns void language plpgsql security definer set search_path='' as $$
declare g uuid;w uuid;begin
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role::text in ('admin','mvz','recepcion')) then raise exception 'contact_read_required';end if;
 if p_write then
  perform 1 from public.clinics where id=p_clinic for update;
  perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 end if;
 g=private.permission_require(p_clinic,'patient.read');
 if not exists(select 1 from private.member_permission_grants where id=g and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 if p_write then
  w=private.permission_require(p_clinic,'patient.write');
  if not exists(select 1 from private.member_permission_grants where id=w and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 end if;
end$$;
revoke all on function private.patient_contact_guard(uuid,boolean) from public,anon,authenticated;
create function public.patient_contact_snapshot(p_clinic uuid,p_patient uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.vet_owners;p public.vet_patients;begin
 perform private.patient_contact_guard(p_clinic,false);
 select * into p from public.vet_patients where clinic_id=p_clinic and id=p_patient;
 if not found then raise exception 'patient_unavailable';end if;
 select * into o from public.vet_owners where clinic_id=p_clinic and id=p.owner_id;
 return jsonb_build_object('schema_version',1,'clinic_id',p_clinic,'patient_id',p_patient,
  'owner',case when o.id is null then null else jsonb_build_object('id',o.id,'name',o.name,'phone',o.phone,'phone_alt',o.phone_alt,
    'email',o.email,'address',o.address,'contact_name',o.contact_name,'contact_phone',o.contact_phone,
    'contact_relationship',o.contact_relationship,'contact_authorized',o.contact_authorized,'contact_version',o.contact_version) end,
  'can_write',private.permission_effective(p_clinic,auth.uid(),'patient.write') is not null,
  'attempts',coalesce((select jsonb_agg(to_jsonb(x)-'clinic_id'-'patient_id' order by occurred_at desc,created_at desc,id)
    from public.patient_contact_attempts x where clinic_id=p_clinic and patient_id=p_patient),'[]'));
end$$;
create function public.patient_contact_save(p_clinic uuid,p_patient uuid,p_owner uuid,p_version integer,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare o public.vet_owners;fp jsonb;receipt uuid;k text;v text;new_data jsonb;begin
 perform private.patient_contact_guard(p_clinic,true);
 if not exists(select 1 from public.vet_patients where clinic_id=p_clinic and id=p_patient and owner_id=p_owner) then raise exception 'patient_owner_changed';end if;
 select * into o from public.vet_owners where clinic_id=p_clinic and id=p_owner for update;
 if not found then raise exception 'owner_unavailable';end if;
 fp=jsonb_build_object('kind','patient_contact_save','patient',p_patient,'owner',p_owner,'version',p_version,'data',p_data);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);
 perform private.patient_contact_guard(p_clinic,true);
 if receipt is not null then return receipt;end if;
 if p_version is distinct from o.contact_version then raise exception 'contact_version_conflict';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>10000 then raise exception 'invalid_contact';end if;
 if exists(select 1 from jsonb_object_keys(p_data) x where x not in ('name','phone','phone_alt','email','address','contact_name','contact_phone','contact_relationship','contact_authorized')) then raise exception 'unsupported_contact_field';end if;
 new_data='{}';
 foreach k in array array['name','phone','phone_alt','email','address','contact_name','contact_phone','contact_relationship'] loop
  if jsonb_typeof(p_data->k) is distinct from 'string' then raise exception 'invalid_contact';end if;
  v=btrim(p_data->>k);
  if length(v)>(case when k='address' then 1000 when k='name' then 200 else 300 end) or (k='name' and v='') then raise exception 'invalid_contact';end if;
  new_data=new_data||jsonb_build_object(k,v);
 end loop;
 if jsonb_typeof(p_data->'contact_authorized') is distinct from 'boolean' then raise exception 'invalid_contact';end if;
 new_data=new_data||jsonb_build_object('contact_authorized',p_data->'contact_authorized');
 if ((new_data->>'contact_name'<>'')<>(new_data->>'contact_phone'<>'')) or
   (new_data->'contact_authorized'='true'::jsonb and new_data->>'contact_name'='') then raise exception 'complete_contact_required';end if;
 insert into private.owner_contact_revisions(clinic_id,owner_id,version,previous_data,new_data,recorded_by)
 values(p_clinic,p_owner,o.contact_version,to_jsonb(o)-'created_by'-'created_at',new_data,auth.uid()) returning id into receipt;
 update public.vet_owners set name=new_data->>'name',phone=new_data->>'phone',phone_alt=new_data->>'phone_alt',
 email=new_data->>'email',address=new_data->>'address',contact_name=new_data->>'contact_name',
 contact_phone=new_data->>'contact_phone',contact_relationship=new_data->>'contact_relationship',
 contact_authorized=(new_data->>'contact_authorized')::boolean,contact_version=contact_version+1
 where id=p_owner and clinic_id=p_clinic;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,receipt);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'owner_contact_updated',p_owner::text);
 return receipt;
end$$;
create function public.patient_contact_log(p_clinic uuid,p_patient uuid,p_owner uuid,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare fp jsonb;receipt uuid;k text;t timestamptz;begin
 perform private.patient_contact_guard(p_clinic,true);
 if not exists(select 1 from public.vet_patients where clinic_id=p_clinic and id=p_patient and owner_id=p_owner) then raise exception 'patient_owner_changed';end if;
 fp=jsonb_build_object('kind','patient_contact_log','patient',p_patient,'owner',p_owner,'data',p_data);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);
 perform private.patient_contact_guard(p_clinic,true);
 if receipt is not null then return receipt;end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>10000 then raise exception 'invalid_contact_attempt';end if;
 foreach k in array array['recipient','method','outcome','occurred_at'] loop
  if jsonb_typeof(p_data->k) is distinct from 'string' or btrim(p_data->>k)='' then raise exception 'invalid_contact_attempt';end if;
 end loop;
 if p_data ? 'notes' and jsonb_typeof(p_data->'notes') is distinct from 'string' then raise exception 'invalid_contact_attempt';end if;
 t=(p_data->>'occurred_at')::timestamptz;
 if t>clock_timestamp() or t<'1900-01-01'::timestamptz then raise exception 'invalid_contact_attempt_time';end if;
 insert into public.patient_contact_attempts(clinic_id,patient_id,owner_id,recipient,method,outcome,occurred_at,notes,recorded_by)
 values(p_clinic,p_patient,p_owner,btrim(p_data->>'recipient'),p_data->>'method',p_data->>'outcome',t,coalesce(p_data->>'notes',''),auth.uid()) returning id into receipt;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,receipt);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'patient_contact_attempt_recorded',receipt::text);
 return receipt;
end$$;

-- Charge state is derived exclusively from service acts and active POS sale lines.
-- Payment-reference reports are observational and must never be counted again.
create function public.appointment_patient_links(p_clinic uuid,p_appointments uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare contacts boolean;finance boolean;begin
 perform private.permission_require(p_clinic,'appointment.read');
 if p_appointments is null or cardinality(p_appointments)>100 then raise exception 'appointment_batch_required';end if;
 contacts=private.permission_effective(p_clinic,auth.uid(),'patient.read') is not null
  and exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and role::text in ('admin','mvz','recepcion'));
 finance=private.permission_effective(p_clinic,auth.uid(),'sales.read') is not null
  and private.permission_effective(p_clinic,auth.uid(),'inventory.read') is not null;
 return jsonb_build_object('schema_version',1,'clinic_id',p_clinic,
 'appointments',coalesce((select jsonb_agg(jsonb_build_object('appointment_id',a.id,
  'contact',case when contacts and o.id is not null then jsonb_build_object(
    'id',o.id,'name',o.name,'phone',o.phone,'phone_alt',o.phone_alt,'address',o.address,
    'contact_name',o.contact_name,'contact_phone',o.contact_phone,'contact_authorized',o.contact_authorized) else null end,
  'billing',case when not finance then null else (
    select jsonb_build_object('total',coalesce(sum(c.price),0)::text,'paid',coalesce(sum(c.paid),0)::text,
      'charge_count',count(*),'state',case when count(*)=0 then 'no_charge'
        when bool_or(c.paid>c.price or c.paid<0) then 'review'
        when sum(c.paid)=sum(c.price) then 'paid' when sum(c.paid)=0 then 'unpaid' else 'partial' end)
    from (select act.price,coalesce((select sum(l.total) from public.inventory_sale_lines l
      join public.inventory_sales s on s.id=l.sale_id and s.clinic_id=l.clinic_id
      where l.clinic_id=p_clinic and l.kind='servicio' and l.service_act_id=act.id
      and not exists(select 1 from public.inventory_sale_reversals r where r.clinic_id=p_clinic and r.sale_id=s.id)),0) paid
      from public.clinic_service_acts act where act.clinic_id=p_clinic and act.appointment_id=a.id) c
  ) end)) from public.clinic_appointments a
  left join public.vet_patients p on p.clinic_id=a.clinic_id and p.id=a.patient_id
  left join public.vet_owners o on o.clinic_id=p.clinic_id and o.id=p.owner_id
  where a.clinic_id=p_clinic and a.id=any(p_appointments)),'[]'));
end$$;
revoke all on function public.patient_contact_snapshot(uuid,uuid),public.patient_contact_save(uuid,uuid,uuid,integer,jsonb,text),
 public.patient_contact_log(uuid,uuid,uuid,jsonb,text),public.appointment_patient_links(uuid,uuid[]) from public,anon;
grant execute on function public.patient_contact_snapshot(uuid,uuid),public.patient_contact_save(uuid,uuid,uuid,integer,jsonb,text),
 public.patient_contact_log(uuid,uuid,uuid,jsonb,text),public.appointment_patient_links(uuid,uuid[]) to authenticated;
notify pgrst,'reload schema';
commit;
