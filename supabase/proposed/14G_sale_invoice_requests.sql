-- Apply after 14F in the same beta project. Records CFDI requests; it does not issue invoices.
begin;
create table if not exists public.inventory_invoice_requests (
  sale_id uuid primary key,
  clinic_id uuid not null,
  requested_by uuid not null references auth.users(id),
  fiscal_name text not null,
  rfc text not null,
  fiscal_regime text not null,
  postal_code text not null,
  cfdi_use text not null,
  email text not null,
  status text not null default 'pendiente' check (status in ('pendiente','emitida','cancelada')),
  requested_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (clinic_id,sale_id) references public.inventory_sales(clinic_id,id)
);
alter table public.inventory_invoice_requests enable row level security;
revoke all on public.inventory_invoice_requests from public,anon,authenticated;

create or replace function public.inv_invoice_request(p_sale uuid,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare s public.inventory_sales; n text; r text; regime text; postal text; cfdi text; mail text;
begin
  select * into s from public.inventory_sales where id=p_sale;
  if not found or not private.inventory_current(s.clinic_id,'sales.collect') then
    raise exception 'cash_collection_permission_required';
  end if;
  if exists(select 1 from public.inventory_sale_reversals where clinic_id=s.clinic_id and sale_id=s.id) then
    raise exception 'invoice_reversed_sale';
  end if;
  n=pg_catalog.btrim(coalesce(p_data->>'fiscal_name',''));
  r=pg_catalog.upper(pg_catalog.btrim(coalesce(p_data->>'rfc','')));
  regime=pg_catalog.btrim(coalesce(p_data->>'fiscal_regime',''));
  postal=pg_catalog.btrim(coalesce(p_data->>'postal_code',''));
  cfdi=pg_catalog.upper(pg_catalog.btrim(coalesce(p_data->>'cfdi_use','')));
  mail=pg_catalog.btrim(coalesce(p_data->>'email',''));
  if pg_catalog.length(n) not between 2 and 200
    or r !~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'
    or regime !~ '^[0-9]{3}$'
    or postal !~ '^[0-9]{5}$'
    or cfdi !~ '^[A-Z0-9]{3}$'
    or pg_catalog.length(mail) not between 5 and 254
    or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'invoice_fiscal_data_invalid';
  end if;
  insert into public.inventory_invoice_requests
    (sale_id,clinic_id,requested_by,fiscal_name,rfc,fiscal_regime,postal_code,cfdi_use,email)
  values (s.id,s.clinic_id,auth.uid(),n,r,regime,postal,cfdi,mail)
  on conflict (sale_id) do update set
    fiscal_name=excluded.fiscal_name,rfc=excluded.rfc,fiscal_regime=excluded.fiscal_regime,
    postal_code=excluded.postal_code,cfdi_use=excluded.cfdi_use,email=excluded.email,
    requested_by=auth.uid(),updated_at=clock_timestamp()
  where public.inventory_invoice_requests.status='pendiente';
  if not found then raise exception 'invoice_request_already_processed';end if;
end$$;
revoke all on function public.inv_invoice_request(uuid,jsonb) from public,anon;
grant execute on function public.inv_invoice_request(uuid,jsonb) to authenticated;

create or replace function public.inv_invoice_requests(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.inventory_current(p_clinic,'sales.read') then
    raise exception 'inventory_read_permission_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'sale_id',r.sale_id,'total',s.total::text,'created_at',s.created_at,
    'fiscal_name',r.fiscal_name,'rfc',r.rfc,'fiscal_regime',r.fiscal_regime,
    'postal_code',r.postal_code,'cfdi_use',r.cfdi_use,'email',r.email,
    'status',r.status,'requested_at',r.requested_at
  ) order by r.requested_at desc)
  from public.inventory_invoice_requests r
  join public.inventory_sales s on s.id=r.sale_id and s.clinic_id=r.clinic_id
  where r.clinic_id=p_clinic),'[]'::jsonb);
end$$;
revoke all on function public.inv_invoice_requests(uuid) from public,anon;
grant execute on function public.inv_invoice_requests(uuid) to authenticated;
commit;
notify pgrst, 'reload schema';
