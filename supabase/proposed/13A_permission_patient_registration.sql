-- Stage 2B-1, LOCAL CANDIDATE ONLY: demographic registration, not clinical records.
-- No remote application until coordinated cutover of RPC/RLS/Storage/Edge/UI.
begin;
do $$begin
 if not (select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
 if exists(select 1 from pg_policies where schemaname='public' and tablename in ('vet_patients','vet_owners')
 and policyname not in ('vet_patient_read','vet_owner_read')) then raise exception 'unreviewed_patient_policy';end if;
end$$;
create function private.permission_patient_read(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.permission_effective(p_clinic,auth.uid(),'patient.read') is not null;
$$;
revoke all on function private.permission_patient_read(uuid) from public,anon;
grant execute on function private.permission_patient_read(uuid) to authenticated;
drop policy vet_owner_read on public.vet_owners;
drop policy vet_patient_read on public.vet_patients;
create policy vet_owner_read on public.vet_owners for select to authenticated using(private.permission_patient_read(clinic_id));
create policy vet_patient_read on public.vet_patients for select to authenticated using(private.permission_patient_read(clinic_id));
create or replace function public.create_vet_patient(p_clinic_id uuid,p_patient jsonb,p_owner jsonb,p_operation_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare grant_id uuid;v_id uuid;owner uuid;fingerprint jsonb;birth date;field text;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 -- Same clinic lock as grant/revocation administration; held through the write.
 perform 1 from public.clinics where id=p_clinic_id for update;
 perform 1 from public.clinic_members where clinic_id=p_clinic_id and user_id=auth.uid() for share;
 grant_id=private.permission_require(p_clinic_id,'patient.write');
 -- A request that waited for a lock must not use an already expired grant.
 if not exists(select 1 from private.member_permission_grants where id=grant_id and valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
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
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic_id,auth.uid(),'patient_created',v_id,jsonb_build_object('permission_grant_id',grant_id));
 return v_id;
end $$;
revoke all on function public.create_vet_patient(uuid,jsonb,jsonb,text) from public,anon;
grant execute on function public.create_vet_patient(uuid,jsonb,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
