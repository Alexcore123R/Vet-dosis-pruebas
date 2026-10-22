-- Apply after 14L and 14J. Consent by purpose, promotion fields and inventory evidence.
begin;
alter table public.clinic_promotions add column if not exists service_name text not null default '' check(length(service_name)<=150);
alter table public.clinic_promotions add column if not exists conditions text not null default '' check(length(conditions)<=2000);

create table if not exists public.client_service_contact_preferences (
 clinic_id uuid not null,owner_id uuid not null,
 purpose text not null check(purpose in ('appointment','follow_up')),
 whatsapp_allowed boolean not null default false,email_allowed boolean not null default false,
 consent_source text not null default '' check(length(consent_source)<=300),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 primary key(clinic_id,owner_id,purpose),
 foreign key(clinic_id,owner_id) references public.vet_owners(clinic_id,id)
);
alter table public.client_service_contact_preferences enable row level security;
revoke all on public.client_service_contact_preferences from public,anon,authenticated;

create or replace function public.ops_appointment_contact(p_clinic uuid,p_appointment uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not (private.ops_permission_active(p_clinic,'appointment.read') or private.ops_permission_active(p_clinic,'appointment.manage')) or not private.permission_patient_read(p_clinic) then raise exception 'appointment_patient_read_required';end if;
 select jsonb_build_object('appointment_id',a.id,'version',a.version,'state',a.state,'kind',a.kind,
  'starts_local',to_char(a.starts_at at time zone private.inv_timezone(p_clinic),'YYYY-MM-DD HH24:MI'),'timezone',private.inv_timezone(p_clinic),
  'owner_id',o.id,'name',o.name,'phone',o.phone,'email',o.email,
  'can_record',private.ops_permission_active(p_clinic,'patient.write'),
  'preferences',coalesce((select jsonb_object_agg(c.purpose,jsonb_build_object('whatsapp_allowed',c.whatsapp_allowed,'email_allowed',c.email_allowed,'consent_source',c.consent_source)) from public.client_service_contact_preferences c where c.clinic_id=p_clinic and c.owner_id=o.id),'{}'))
 into result from public.clinic_appointments a
 left join public.vet_patients p on p.id=a.patient_id and p.clinic_id=a.clinic_id
 left join public.vet_owners o on o.id=p.owner_id and o.clinic_id=p.clinic_id
 where a.id=p_appointment and a.clinic_id=p_clinic;
 if result is null then raise exception 'appointment_not_found';end if;
 return result;
end$$;
revoke all on function public.ops_appointment_contact(uuid,uuid) from public,anon;
grant execute on function public.ops_appointment_contact(uuid,uuid) to authenticated;

create or replace function public.ops_service_contact_save(p_clinic uuid,p_owner uuid,p_purpose text,p_whatsapp boolean,p_email boolean,p_source text)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.permission_require(p_clinic,'patient.write');
 if not private.ops_permission_active(p_clinic,'patient.write') then raise exception 'patient_write_required';end if;
 if p_purpose is null or p_purpose not in ('appointment','follow_up') then raise exception 'invalid_contact_purpose';end if;
 if not exists(select 1 from public.vet_owners where clinic_id=p_clinic and id=p_owner) then raise exception 'owner_wrong_clinic';end if;
 if (coalesce(p_whatsapp,false) or coalesce(p_email,false)) and length(btrim(coalesce(p_source,''))) not between 5 and 300 then raise exception 'contact_consent_source_required';end if;
 insert into public.client_service_contact_preferences(clinic_id,owner_id,purpose,whatsapp_allowed,email_allowed,consent_source,recorded_by)
 values(p_clinic,p_owner,p_purpose,coalesce(p_whatsapp,false),coalesce(p_email,false),left(btrim(coalesce(p_source,'')),300),auth.uid())
 on conflict(clinic_id,owner_id,purpose) do update set whatsapp_allowed=excluded.whatsapp_allowed,email_allowed=excluded.email_allowed,consent_source=excluded.consent_source,recorded_by=auth.uid(),recorded_at=clock_timestamp();
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'service_contact_preferences',p_owner::text,jsonb_build_object('purpose',p_purpose,'whatsapp',p_whatsapp,'email',p_email));
end$$;
revoke all on function public.ops_service_contact_save(uuid,uuid,text,boolean,boolean,text) from public,anon;
grant execute on function public.ops_service_contact_save(uuid,uuid,text,boolean,boolean,text) to authenticated;

create or replace function public.ops_promotion_save(p_clinic uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_kind text;v_title text;v_message text;v_discount numeric;v_start date;v_end date;v_service text;v_conditions text;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 v_id=nullif(p_data->>'id','')::uuid;
 if p_data->>'archive'='true' then
  update public.clinic_promotions set active=false where clinic_id=p_clinic and id=v_id;
  if not found then raise exception 'promotion_not_found';end if;return v_id;
 end if;
 v_kind=p_data->>'kind';v_title=btrim(coalesce(p_data->>'title',''));v_message=btrim(coalesce(p_data->>'message',''));
 v_service=btrim(coalesce(p_data->>'service_name',''));v_conditions=btrim(coalesce(p_data->>'conditions',''));
 v_discount=nullif(p_data->>'discount_percent','')::numeric;v_start=nullif(p_data->>'starts_on','')::date;v_end=nullif(p_data->>'ends_on','')::date;
 if v_kind is null or v_kind not in ('promocion','recompensa','evento') or length(v_title) not between 3 and 150 or length(v_message) not between 5 and 2000 or length(v_service)>150 or length(v_conditions)>2000
 or (v_discount is not null and (v_discount<0 or v_discount>100)) or (v_start is not null and v_end is not null and v_end<v_start) then raise exception 'promotion_fields_invalid';end if;
 if v_id is null then
  insert into public.clinic_promotions(clinic_id,kind,title,message,discount_percent,starts_on,ends_on,service_name,conditions,created_by)
  values(p_clinic,v_kind,v_title,v_message,v_discount,v_start,v_end,v_service,v_conditions,auth.uid()) returning id into v_id;
 else
  update public.clinic_promotions set kind=v_kind,title=v_title,message=v_message,discount_percent=v_discount,starts_on=v_start,ends_on=v_end,service_name=v_service,conditions=v_conditions
  where clinic_id=p_clinic and id=v_id and active;
  if not found then raise exception 'promotion_not_found';end if;
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'promotion_save',v_id::text,jsonb_build_object('kind',v_kind));return v_id;
end$$;

create or replace function public.inv_ai_insights(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date;boundary timestamptz;previous_boundary timestamptz;end_at timestamptz;can_sales boolean;
begin
 if not private.inv_access(p_clinic) then raise exception 'inventory_access_required';end if;
 today=(clock_timestamp() at time zone private.inv_timezone(p_clinic))::date;
 boundary=(today-29)::timestamp at time zone private.inv_timezone(p_clinic);
 previous_boundary=(today-59)::timestamp at time zone private.inv_timezone(p_clinic);
 end_at=(today+1)::timestamp at time zone private.inv_timezone(p_clinic);
 can_sales=private.inventory_current(p_clinic,'sales.read');
 return jsonb_build_object('today',today,'timezone',private.inv_timezone(p_clinic),'sales_allowed',can_sales,
 'current_from',today-29,'current_to',today,'previous_from',today-59,'previous_to',today-30,
 'products',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.nombre,'unit',i.stock_unit,'available',a.qty::text,'minimum',i.stock_minimo::text,'reorder_point',i.reorder_point::text,'low_stock',a.qty<=i.stock_minimo,'reorder',a.qty<=i.reorder_point) order by i.nombre)
 from public.inventario i cross join lateral(select coalesce(sum(l.cantidad),0) qty from public.lotes_inventario l where l.clinic_id=p_clinic and l.item_id=i.id and (l.caducidad>today or (l.caducidad is null and i.m8_kind='producto'))) a
 where i.clinic_id=p_clinic and i.active and i.m8_enabled),'[]'),
 'lots',coalesce((select jsonb_agg(jsonb_build_object('item_id',i.id,'name',i.nombre,'lot',l.lote,'unit',i.stock_unit,'expiry',l.caducidad,'days',l.caducidad-today,'quantity',l.cantidad::text,'expired',l.caducidad<=today) order by l.caducidad)
 from public.lotes_inventario l join public.inventario i on i.id=l.item_id and i.clinic_id=l.clinic_id
 where l.clinic_id=p_clinic and i.active and i.m8_enabled and l.cantidad>0 and l.caducidad<=today+90),'[]'),
 'sales',case when can_sales then coalesce((
  select jsonb_agg(jsonb_build_object('item_id',x.item_id,'name',i.nombre,'unit',i.stock_unit,'current_quantity',x.current_qty::text,'previous_quantity',x.previous_qty::text,'current_amount',x.current_amount::text,'previous_amount',x.previous_amount::text) order by x.current_amount desc)
  from (select e.item_id,sum(case when e.occurred_at>=boundary then e.qty else 0 end) current_qty,sum(case when e.occurred_at<boundary then e.qty else 0 end) previous_qty,
   sum(case when e.occurred_at>=boundary then e.amount else 0 end) current_amount,sum(case when e.occurred_at<boundary then e.amount else 0 end) previous_amount
   from (
    select l.item_id,l.quantity qty,l.total amount,s.created_at occurred_at from public.inventory_sale_lines l join public.inventory_sales s on s.id=l.sale_id and s.clinic_id=l.clinic_id where l.clinic_id=p_clinic and l.kind='producto' and s.created_at>=previous_boundary and s.created_at<end_at
    union all
    select l.item_id,-l.quantity,-l.total,r.created_at from public.inventory_sale_lines l join public.inventory_sale_reversals r on r.sale_id=l.sale_id and r.clinic_id=l.clinic_id where l.clinic_id=p_clinic and l.kind='producto' and r.created_at>=previous_boundary and r.created_at<end_at
   ) e group by e.item_id) x join public.inventario i on i.id=x.item_id and i.clinic_id=p_clinic
 ),'[]') else '[]'::jsonb end);
end$$;
revoke all on function public.inv_ai_insights(uuid) from public,anon;
grant execute on function public.inv_ai_insights(uuid) to authenticated;
select private.beta_install_guards();
commit;
notify pgrst, 'reload schema';
