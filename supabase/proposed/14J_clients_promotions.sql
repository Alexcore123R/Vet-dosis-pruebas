-- Apply after 14I. Client directory and consent-gated, manually shared offers.
begin;
create table if not exists public.client_marketing_preferences (
  clinic_id uuid not null,
  owner_id uuid not null,
  whatsapp_allowed boolean not null default false,
  email_allowed boolean not null default false,
  consent_source text not null default '',
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default clock_timestamp(),
  primary key(clinic_id,owner_id),
  foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id)
);
alter table public.client_marketing_preferences enable row level security;
revoke all on public.client_marketing_preferences from public,anon,authenticated;

create table if not exists public.clinic_promotions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id),
  kind text not null check(kind in ('promocion','recompensa','evento')),
  title text not null check(length(btrim(title)) between 3 and 150),
  message text not null check(length(btrim(message)) between 5 and 2000),
  discount_percent numeric(5,2) check(discount_percent between 0 and 100),
  starts_on date,
  ends_on date,
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  check(ends_on is null or starts_on is null or ends_on>=starts_on)
);
alter table public.clinic_promotions enable row level security;
revoke all on public.clinic_promotions from public,anon,authenticated;

create or replace function public.ops_client_directory(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.permission_patient_read(p_clinic) then raise exception 'patient_read_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',o.id,'name',o.name,'phone',o.phone,'whatsapp',o.phone,'email',o.email,'address',o.address,
  'whatsapp_allowed',coalesce(m.whatsapp_allowed,false),
  'email_allowed',coalesce(m.email_allowed,false),
  'consent_source',coalesce(m.consent_source,'')
 ) order by o.name) from public.vet_owners o
 left join public.client_marketing_preferences m on m.clinic_id=o.clinic_id and m.owner_id=o.id
 where o.clinic_id=p_clinic),'[]'::jsonb);
end$$;
revoke all on function public.ops_client_directory(uuid) from public,anon;
grant execute on function public.ops_client_directory(uuid) to authenticated;

create or replace function public.ops_marketing_preferences_save(p_clinic uuid,p_owner uuid,p_whatsapp boolean,p_email boolean,p_source text)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.permission_require(p_clinic,'patient.write');
 if not exists(select 1 from public.vet_owners where clinic_id=p_clinic and id=p_owner) then raise exception 'owner_wrong_clinic';end if;
 if (coalesce(p_whatsapp,false) or coalesce(p_email,false)) and
    length(btrim(coalesce(p_source,''))) not between 5 and 300 then raise exception 'marketing_consent_source_required';end if;
 insert into public.client_marketing_preferences(clinic_id,owner_id,whatsapp_allowed,email_allowed,consent_source,recorded_by)
 values(p_clinic,p_owner,coalesce(p_whatsapp,false),coalesce(p_email,false),left(btrim(coalesce(p_source,'')),300),auth.uid())
 on conflict(clinic_id,owner_id) do update set whatsapp_allowed=excluded.whatsapp_allowed,email_allowed=excluded.email_allowed,
  consent_source=excluded.consent_source,recorded_by=auth.uid(),recorded_at=clock_timestamp();
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'marketing_preferences',p_owner::text,jsonb_build_object('whatsapp',p_whatsapp,'email',p_email));
end$$;
revoke all on function public.ops_marketing_preferences_save(uuid,uuid,boolean,boolean,text) from public,anon;
grant execute on function public.ops_marketing_preferences_save(uuid,uuid,boolean,boolean,text) to authenticated;

create or replace function public.ops_promotions(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.permission_patient_read(p_clinic) then raise exception 'patient_read_required';end if;
 return coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.clinic_promotions p where p.clinic_id=p_clinic),'[]'::jsonb);
end$$;
revoke all on function public.ops_promotions(uuid) from public,anon;
grant execute on function public.ops_promotions(uuid) to authenticated;

create or replace function public.ops_promotion_save(p_clinic uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_kind text;v_title text;v_message text;v_discount numeric;v_start date;v_end date;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 v_id=nullif(p_data->>'id','')::uuid;
 if p_data->>'archive'='true' then
  update public.clinic_promotions set active=false where clinic_id=p_clinic and id=v_id;
  if not found then raise exception 'promotion_not_found';end if;
  return v_id;
 end if;
 v_kind=p_data->>'kind';v_title=btrim(coalesce(p_data->>'title',''));v_message=btrim(coalesce(p_data->>'message',''));
 v_discount=nullif(p_data->>'discount_percent','')::numeric;
 v_start=nullif(p_data->>'starts_on','')::date;v_end=nullif(p_data->>'ends_on','')::date;
 if v_kind not in ('promocion','recompensa','evento') or length(v_title) not between 3 and 150
  or length(v_message) not between 5 and 2000 or (v_discount is not null and (v_discount<0 or v_discount>100))
  or (v_start is not null and v_end is not null and v_end<v_start) then raise exception 'promotion_fields_invalid';end if;
 if v_id is null then
  insert into public.clinic_promotions(clinic_id,kind,title,message,discount_percent,starts_on,ends_on,created_by)
  values(p_clinic,v_kind,v_title,v_message,v_discount,v_start,v_end,auth.uid()) returning id into v_id;
 else
  update public.clinic_promotions set kind=v_kind,title=v_title,message=v_message,discount_percent=v_discount,starts_on=v_start,ends_on=v_end
  where id=v_id and clinic_id=p_clinic and active;
  if not found then raise exception 'promotion_not_found';end if;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details)
 values(p_clinic,auth.uid(),'promotion_save',v_id::text,jsonb_build_object('kind',v_kind));
 return v_id;
end$$;
revoke all on function public.ops_promotion_save(uuid,jsonb) from public,anon;
grant execute on function public.ops_promotion_save(uuid,jsonb) to authenticated;
commit;
notify pgrst, 'reload schema';
