-- Apply after 14D. A catalog service may use a one-sale price or update its future price atomically with the sale.
begin;
create table if not exists public.inventory_catalog_service_sales (
 clinic_id uuid not null references public.clinics(id),
 actor_id uuid not null references auth.users(id),
 operation_id text not null check(operation_id~'^[a-f0-9]{48}$'),
 sale_id uuid not null,
 fingerprint jsonb not null,
 changes jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(clinic_id,actor_id,operation_id),
 foreign key(clinic_id,sale_id) references public.inventory_sales(clinic_id,id)
);
alter table public.inventory_catalog_service_sales enable row level security;
revoke all on public.inventory_catalog_service_sales from public,anon,authenticated;

create or replace function public.inv_catalog_services(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.inventory_current(p_clinic,'sales.manual') then raise exception 'explicit_permission_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',s.id,'name',s.name,'price',s.price::text,'version',s.version,'active',s.active
 ) order by s.name) from public.clinic_services s where s.clinic_id=p_clinic and s.active),'[]'::jsonb);
end$$;
revoke all on function public.inv_catalog_services(uuid) from public,anon;
grant execute on function public.inv_catalog_services(uuid) to authenticated;

create or replace function public.inv_catalog_service_sale_post(
 p_shift uuid,p_method text,p_lines jsonb,p_expected_total text,p_operation text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 sh public.inventory_cash_shifts;
 service public.clinic_services;
 existing public.inventory_catalog_service_sales;
 line jsonb;
 clean_lines jsonb='[]'::jsonb;
 changes jsonb='[]'::jsonb;
 fingerprint jsonb;
 sale_id uuid;
 service_id uuid;
 seen uuid[]='{}'::uuid[];
 mode text;
 new_price numeric;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 select * into sh from public.inventory_cash_shifts where id=p_shift;
 if not found or sh.cashier_id<>auth.uid() then raise exception 'own_shift_required';end if;
 if p_operation is null or p_operation !~ '^[a-f0-9]{48}$' then raise exception 'invalid_operation';end if;
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 50 then raise exception 'sale_lines_required';end if;
 fingerprint=jsonb_build_object('shift',p_shift,'method',p_method,'lines',p_lines,'total',p_expected_total);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text||sh.clinic_id::text||p_operation,0));
 select * into existing from public.inventory_catalog_service_sales
 where clinic_id=sh.clinic_id and actor_id=auth.uid() and operation_id=p_operation;
 if found then
  if existing.fingerprint<>fingerprint then raise exception 'operation_payload_changed';end if;
  return existing.sale_id;
 end if;
 for service_id in
  select distinct (e->>'catalog_service_id')::uuid from jsonb_array_elements(p_lines) e
  where nullif(e->>'catalog_service_id','') is not null order by 1
 loop
  perform 1 from public.clinic_services where clinic_id=sh.clinic_id and id=service_id for update;
 end loop;
 for line in select value from jsonb_array_elements(p_lines) loop
  service_id=nullif(line->>'catalog_service_id','')::uuid;
  if service_id is null then
   clean_lines=clean_lines||jsonb_build_array(line);
   continue;
  end if;
  if line->>'kind'<>'servicio' or service_id=any(seen) then raise exception 'catalog_service_line_invalid';end if;
  seen=array_append(seen,service_id);
  select * into service from public.clinic_services where clinic_id=sh.clinic_id and id=service_id and active;
  if not found or service.version<>nullif(line->>'catalog_service_version','')::integer then raise exception 'service_version_changed';end if;
  mode=line->>'catalog_price_mode';
  if mode not in ('solo_venta','actualizar_catalogo') then raise exception 'catalog_price_mode_required';end if;
  new_price=private.inv_money(line->>'price');
  if new_price<=0 then raise exception 'service_price_required';end if;
  if mode='actualizar_catalogo' then
   if not private.has_clinic_role(sh.clinic_id,array['admin']) then raise exception 'admin_required';end if;
   perform private.permission_require(sh.clinic_id,'service.manage');
   if service.commission_kind='bono' and new_price<service.commission_value then
    raise exception 'price_below_service_commission';
   end if;
  end if;
  clean_lines=clean_lines||jsonb_build_array(jsonb_build_object(
   'kind','servicio','name',service.name,'quantity',line->>'quantity',
   'price',new_price::text,'cost',private.inv_money(line->>'cost')::text,'commission','0.00'
  ));
  changes=changes||jsonb_build_array(jsonb_build_object(
   'service_id',service.id,'service_version',service.version,'name',service.name,
   'old_price',service.price::text,'sale_price',new_price::text,'mode',mode
  ));
 end loop;
 if jsonb_array_length(changes)=0 then raise exception 'catalog_service_required';end if;
 -- The existing cashier RPC validates the shift, every product/lot, and the exact customer total.
 -- A failed catalog update rolls back that sale in the same transaction.
 sale_id=public.inv_sale_post(p_shift,p_method,clean_lines,p_expected_total,p_operation);
 for line in select value from jsonb_array_elements(changes) loop
  if line->>'mode'='actualizar_catalogo' and (line->>'sale_price')::numeric<>(line->>'old_price')::numeric then
   update public.clinic_services set price=(line->>'sale_price')::numeric,version=version+1,updated_at=clock_timestamp()
   where clinic_id=sh.clinic_id and id=(line->>'service_id')::uuid and version=(line->>'service_version')::integer;
   if not found then raise exception 'service_version_changed';end if;
  end if;
 end loop;
 insert into public.inventory_catalog_service_sales(clinic_id,actor_id,operation_id,sale_id,fingerprint,changes)
 values(sh.clinic_id,auth.uid(),p_operation,sale_id,fingerprint,changes);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(sh.clinic_id,auth.uid(),'inventory_catalog_service_sale',sale_id::text,jsonb_build_object('changes',changes));
 return sale_id;
end$$;
revoke all on function public.inv_catalog_service_sale_post(uuid,text,jsonb,text,text) from public,anon;
grant execute on function public.inv_catalog_service_sale_post(uuid,text,jsonb,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
