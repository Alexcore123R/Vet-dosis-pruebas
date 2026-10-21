-- Apply after 14H. Explicit clinic contacts, without importing the device phonebook.
begin;
create table if not exists public.clinic_staff_contacts (
  clinic_id uuid not null references public.clinics(id),
  user_id uuid not null references auth.users(id),
  phone text not null default '',
  whatsapp text not null default '',
  email text not null default '',
  address text not null default '',
  updated_at timestamptz not null default clock_timestamp(),
  primary key(clinic_id,user_id),
  foreign key(clinic_id,user_id) references public.clinic_members(clinic_id,user_id)
);
alter table public.clinic_staff_contacts enable row level security;
revoke all on public.clinic_staff_contacts from public,anon,authenticated;
alter table public.clinic_suppliers add column if not exists address text not null default '';

create or replace function public.ops_contact_directory(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_ok boolean; supplier_ok boolean;
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 team_ok=private.ops_permission_active(p_clinic,'team.read') or private.ops_permission_active(p_clinic,'team.manage');
 supplier_ok=private.ops_permission_active(p_clinic,'supplier.read') or private.ops_permission_active(p_clinic,'supplier.manage');
 return jsonb_build_object(
  'team_allowed',team_ok,'suppliers_allowed',supplier_ok,
  'team_manage',private.ops_permission_active(p_clinic,'team.manage'),
  'supplier_manage',private.ops_permission_active(p_clinic,'supplier.manage'),
  'staff',case when team_ok then coalesce((select jsonb_agg(jsonb_build_object(
    'id',m.user_id,'name',coalesce(nullif(n.name,''),'Personal de la clínica'),
    'phone',coalesce(c.phone,''),'whatsapp',coalesce(c.whatsapp,''),
    'email',coalesce(c.email,''),'address',coalesce(c.address,'')
  ) order by n.name) from public.clinic_members m
  left join public.staff_display_names n on n.clinic_id=m.clinic_id and n.user_id=m.user_id
  left join public.clinic_staff_contacts c on c.clinic_id=m.clinic_id and c.user_id=m.user_id
  where m.clinic_id=p_clinic),'[]'::jsonb) else '[]'::jsonb end,
  'suppliers',case when supplier_ok then coalesce((select jsonb_agg(jsonb_build_object(
    'id',s.id,'name',s.name,'kind',s.kind,'phone',s.phone,'whatsapp',s.whatsapp,
    'email',s.email,'address',s.address
  ) order by s.name) from public.clinic_suppliers s where s.clinic_id=p_clinic and s.active),'[]'::jsonb) else '[]'::jsonb end);
end$$;
revoke all on function public.ops_contact_directory(uuid) from public,anon;
grant execute on function public.ops_contact_directory(uuid) to authenticated;

create or replace function public.ops_contact_save(p_clinic uuid,p_kind text,p_id uuid,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare p text; w text; e text; a text;
begin
 if auth.uid() is null or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'access_denied';end if;
 if p_kind='staff' then
  perform private.permission_require(p_clinic,'team.manage');
  if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=p_id) then raise exception 'contact_not_found';end if;
 elsif p_kind='supplier' then
  perform private.permission_require(p_clinic,'supplier.manage');
  if not exists(select 1 from public.clinic_suppliers where clinic_id=p_clinic and id=p_id and active) then raise exception 'contact_not_found';end if;
 else raise exception 'contact_kind_invalid';end if;
 p=pg_catalog.btrim(coalesce(p_data->>'phone',''));
 w=pg_catalog.btrim(coalesce(p_data->>'whatsapp',''));
 e=pg_catalog.btrim(coalesce(p_data->>'email',''));
 a=pg_catalog.btrim(coalesce(p_data->>'address',''));
 if p !~ '^[0-9+ ()-]{0,30}$' or w !~ '^[0-9+ ()-]{0,30}$'
  or (e<>'' and (pg_catalog.length(e)>254 or e !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
  or pg_catalog.length(a)>500 then raise exception 'contact_fields_invalid';end if;
 if p_kind='staff' then
  insert into public.clinic_staff_contacts(clinic_id,user_id,phone,whatsapp,email,address)
  values(p_clinic,p_id,p,w,e,a)
  on conflict(clinic_id,user_id) do update set phone=excluded.phone,whatsapp=excluded.whatsapp,email=excluded.email,address=excluded.address,updated_at=clock_timestamp();
 else
  update public.clinic_suppliers set phone=p,whatsapp=w,email=e,address=a,updated_at=clock_timestamp()
  where clinic_id=p_clinic and id=p_id and active;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'ops_contact_save',p_id::text,jsonb_build_object('kind',p_kind));
end$$;
revoke all on function public.ops_contact_save(uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.ops_contact_save(uuid,text,uuid,jsonb) to authenticated;
commit;
notify pgrst, 'reload schema';
