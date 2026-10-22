-- Apply after 14D. Extend the existing clinic supplier directory.
begin;
alter table public.clinic_suppliers
  add column if not exists email text not null default '',
  add column if not exists whatsapp text not null default '',
  add column if not exists kind text not null default 'otro',
  add column if not exists balance numeric(18,2) not null default 0,
  add column if not exists visit_on date,
  add column if not exists active boolean not null default true,
  add column if not exists updated_at timestamptz not null default clock_timestamp();
alter table public.clinic_suppliers
  add constraint supplier_balance_nonnegative check(balance>=0);

create or replace function private.ops_catalog_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_grant uuid;v_id uuid;fp jsonb;v_balance numeric;v_phone text;v_whatsapp text;v_email text;v_kind text;v_name text;v_notes text;v_visit date;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 v_grant=private.permission_require(p_clinic,case p_action when 'service' then 'service.manage' when 'supplier' then 'supplier.manage' else null end);
 perform 1 from public.clinics where id=p_clinic for update;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
 fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);
 v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_action='service' then
  if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
  v_id=nullif(p_data->>'id','')::uuid;
  if v_id is null then
   insert into public.clinic_services(clinic_id,name,price,commission_kind,commission_value,category,subcategory)
   values(p_clinic,btrim(p_data->>'name'),private.inv_money(p_data->>'price'),p_data->>'commission_kind',private.inv_money(p_data->>'commission_value'),coalesce(p_data->>'category','otro'),btrim(coalesce(p_data->>'subcategory',''))) returning id into v_id;
  else
   update public.clinic_services set name=btrim(p_data->>'name'),price=private.inv_money(p_data->>'price'),commission_kind=p_data->>'commission_kind',commission_value=private.inv_money(p_data->>'commission_value'),category=coalesce(p_data->>'category',category),subcategory=case when p_data ? 'subcategory' then btrim(coalesce(p_data->>'subcategory','')) else subcategory end,version=version+1,updated_at=clock_timestamp()
   where id=v_id and clinic_id=p_clinic and version=(p_data->>'version')::int;
   if not found then raise exception 'version_conflict';end if;
  end if;
 elsif p_action='supplier' then
  v_id=nullif(p_data->>'id','')::uuid;
  if p_data->>'archive'='true' then
   update public.clinic_suppliers set active=false,updated_at=clock_timestamp()
   where id=v_id and clinic_id=p_clinic and active and balance=0;
   if not found then raise exception 'supplier_archive_blocked';end if;
  else
   v_name=pg_catalog.btrim(coalesce(p_data->>'name',''));
   v_phone=pg_catalog.btrim(coalesce(p_data->>'phone',''));
   v_whatsapp=pg_catalog.btrim(coalesce(p_data->>'whatsapp',''));
   v_email=pg_catalog.btrim(coalesce(p_data->>'email',''));
   v_kind=pg_catalog.btrim(coalesce(p_data->>'kind','otro'));
   v_notes=pg_catalog.btrim(coalesce(p_data->>'notes',''));
   v_balance=private.inv_money(coalesce(nullif(p_data->>'balance',''),'0'));
   v_visit=nullif(p_data->>'visit_on','')::date;
   if pg_catalog.length(v_name) not between 1 and 150
      or v_phone !~ '^[0-9+ ()-]{0,30}$'
      or v_whatsapp !~ '^[0-9+ ()-]{0,30}$'
      or (v_email<>'' and (pg_catalog.length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
      or v_kind not in ('farmacia','alimentos','material','laboratorio','equipo','estetica','servicios','otro')
      or pg_catalog.length(v_notes)>2000 then raise exception 'supplier_fields_invalid';end if;
   if v_id is null then
    insert into public.clinic_suppliers(clinic_id,name,phone,whatsapp,email,kind,balance,visit_on,notes,created_by)
    values(p_clinic,v_name,v_phone,v_whatsapp,v_email,v_kind,v_balance,v_visit,v_notes,auth.uid()) returning id into v_id;
   else
    update public.clinic_suppliers set name=v_name,phone=v_phone,whatsapp=v_whatsapp,email=v_email,kind=v_kind,balance=v_balance,visit_on=v_visit,notes=v_notes,updated_at=clock_timestamp()
    where id=v_id and clinic_id=p_clinic and active;
    if not found then raise exception 'supplier_not_found';end if;
   end if;
  end if;
 else raise exception 'unknown_operation';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'ops_'||p_action,v_id::text,jsonb_build_object('permission_grant_id',v_grant));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
revoke all on function private.ops_catalog_write(uuid,text,jsonb,text) from public,anon,authenticated,service_role;
commit;
notify pgrst, 'reload schema';
