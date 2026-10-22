-- Apply after 13B2; works with or without 13B3 and can be rerun.
-- Custom subcategories are stored with each clinic service.
begin;
alter table public.clinic_services add column if not exists category text not null default 'otro';
alter table public.clinic_services drop constraint if exists clinic_services_category_check;
alter table public.clinic_services add constraint clinic_services_category_check
 check(category in ('consulta','cirugia','hospedaje','hospitalizacion','laboratorio','preventiva','curaciones','estetica','imagen','anestesia','urgencias','domicilio','guarderia','odontologia','rehabilitacion','otro'));
alter table public.clinic_services add column if not exists subcategory text not null default '' check(char_length(subcategory)<=150);
create or replace function private.ops_catalog_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_grant uuid;v_id uuid;fp jsonb;
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
  insert into public.clinic_suppliers(clinic_id,name,phone,notes,created_by)
  values(p_clinic,btrim(p_data->>'name'),coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 else raise exception 'unknown_operation';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'ops_'||p_action,v_id::text,jsonb_build_object('permission_grant_id',v_grant));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
revoke all on function private.ops_catalog_write(uuid,text,jsonb,text) from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;
