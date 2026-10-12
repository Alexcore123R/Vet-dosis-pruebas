-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Ejecutar 05A, 05B, 05C en orden.
-- Sin datos clínicos, productos ni precios de ejemplo.
-- M9. Additive; apply once after M8 workflow. Remote installation pending.
begin;
create table public.clinic_services(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),name text not null check(length(btrim(name)) between 1 and 150),price numeric(18,2) not null check(price>0),commission_kind text not null check(commission_kind in ('porcentaje','bono')),commission_value numeric(18,2) not null check(commission_value>=0),version integer not null default 1,active boolean not null default true,updated_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),check((commission_kind='porcentaje' and commission_value<=100) or (commission_kind='bono' and commission_value<=price)));
create table public.clinic_appointments(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),patient_id uuid,patient_name text not null,species text not null,kind text not null check(kind in ('consulta','estetica')),professional_id uuid not null,starts_at timestamptz not null,ends_at timestamptz not null,state text not null default 'agendado' check(state in ('agendado','en_atencion','listo','entregado','cancelado')),notes text not null default '' check(length(notes)<=2000),version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,professional_id) references public.clinic_members(clinic_id,user_id),check(ends_at>starts_at and ends_at<=starts_at+interval '24 hours'));
create table public.clinic_tasks(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),title text not null check(length(btrim(title)) between 1 and 500),assigned_to uuid,priority text not null check(priority in ('urgente','media','baja')),completed_at timestamptz,completed_by uuid,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,assigned_to) references public.clinic_members(clinic_id,user_id));
create table public.clinic_messages(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),category text not null check(category in ('general','urgente','aviso','turno')),body text not null check(length(btrim(body)) between 1 and 2000),author_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create table public.clinic_suppliers(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),name text not null check(length(btrim(name)) between 1 and 150),phone text not null default '' check(phone~'^[0-9+ ()-]{0,30}$'),notes text not null default '' check(length(notes)<=2000),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create table public.staff_medical_profiles(clinic_id uuid not null,user_id uuid not null,details jsonb not null check(jsonb_typeof(details)='object' and octet_length(details::text)<=16000),consent_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),primary key(clinic_id,user_id),foreign key(clinic_id,user_id) references public.clinic_members(clinic_id,user_id));
create table public.clinic_service_acts(id uuid primary key default gen_random_uuid(),clinic_id uuid not null,service_id uuid not null,professional_id uuid not null,appointment_id uuid references public.clinic_appointments(id),name text not null,service_version integer not null,price numeric(18,2) not null,commission numeric(18,2) not null,commission_kind text not null,commission_value numeric(18,2) not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),foreign key(clinic_id,service_id) references public.clinic_services(clinic_id,id),foreign key(clinic_id,professional_id) references public.clinic_members(clinic_id,user_id));
-- Acts/messages are append-only. Application and dispensing rules remain M6/M8.
create trigger service_act_immutable before update or delete on public.clinic_service_acts for each row execute function private.inv_history_guard();
create trigger message_immutable before update or delete on public.clinic_messages for each row execute function private.inv_history_guard();
do $$declare t text;begin
 foreach t in array array['clinic_services','clinic_appointments','clinic_tasks','clinic_messages','clinic_suppliers','staff_medical_profiles','clinic_service_acts'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end$$;
create function public.ops_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object(
 'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'role',role)),'[]') from public.clinic_members where clinic_id=p_clinic),
 'services',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('price',s.price::text,'commission_value',s.commission_value::text)),'[]') from public.clinic_services s where clinic_id=p_clinic),
 'appointments',(select coalesce(jsonb_agg(to_jsonb(a) order by starts_at),'[]') from public.clinic_appointments a where clinic_id=p_clinic and (private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion']) or professional_id=auth.uid()) and starts_at>clock_timestamp()-interval '90 days'),
 'tasks',(select coalesce(jsonb_agg(to_jsonb(t) order by created_at desc),'[]') from public.clinic_tasks t where clinic_id=p_clinic and (assigned_to is null or assigned_to=auth.uid() or created_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
 'messages',(select coalesce(jsonb_agg(to_jsonb(m) order by created_at),'[]') from (select * from public.clinic_messages where clinic_id=p_clinic order by created_at desc limit 100) m),
 'suppliers',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.clinic_suppliers s where clinic_id=p_clinic and private.has_clinic_role(p_clinic,array['admin','recepcion'])),
 'acts',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('price',a.price::text,'commission',a.commission::text,'paid',exists(select 1 from public.inventory_sale_lines l where l.service_act_id=a.id and not exists(select 1 from public.inventory_sale_reversals r where r.sale_id=l.sale_id)))),'[]') from public.clinic_service_acts a where clinic_id=p_clinic and (professional_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin','recepcion']))));
end$$;
-- Every write locks clinic/member authority, uses server time and logs separately.
create function public.ops_write(p_clinic uuid,p_action text,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_service public.clinic_services;v_appointment public.clinic_appointments;v_prof uuid;v_start timestamptz;v_end timestamptz;fp jsonb;
begin
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for share;
 if not found then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'invalid_data';end if;
 fp=jsonb_build_object('kind','ops','action',p_action,'data',p_data);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_action='service' then
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'admin_required';end if;
 v_id=nullif(p_data->>'id','')::uuid;
 if v_id is null then
 insert into public.clinic_services(clinic_id,name,price,commission_kind,commission_value) values(p_clinic,btrim(p_data->>'name'),private.inv_money(p_data->>'price'),p_data->>'commission_kind',private.inv_money(p_data->>'commission_value')) returning id into v_id;
 else
 update public.clinic_services set name=btrim(p_data->>'name'),price=private.inv_money(p_data->>'price'),commission_kind=p_data->>'commission_kind',commission_value=private.inv_money(p_data->>'commission_value'),version=version+1,updated_at=clock_timestamp() where id=v_id and clinic_id=p_clinic and version=(p_data->>'version')::int;
 if not found then raise exception 'version_conflict';end if;
 end if;
 elsif p_action='appointment' then
 if not private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion','estilista']) then raise exception 'access_denied';end if;
 v_prof=(p_data->>'professional_id')::uuid;v_start=(p_data->>'starts_at')::timestamptz;v_end=(p_data->>'ends_at')::timestamptz;
 if private.has_clinic_role(p_clinic,array['estilista']) and (v_prof<>auth.uid() or p_data->>'kind'<>'estetica') then raise exception 'access_denied';end if;
 perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_prof for update;
 if not found then raise exception 'invalid_professional';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_prof and (p_data->>'kind'='estetica' or role in ('admin','mvz','auxiliar'))) then raise exception 'invalid_professional';end if;
 if exists(select 1 from public.clinic_appointments where clinic_id=p_clinic and professional_id=v_prof and state not in ('cancelado','entregado') and starts_at<v_end and ends_at>v_start) then raise exception 'appointment_overlap';end if;
 insert into public.clinic_appointments(clinic_id,patient_name,species,kind,professional_id,starts_at,ends_at,notes,created_by) values(p_clinic,p_data->>'patient_name',p_data->>'species',p_data->>'kind',v_prof,v_start,v_end,coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 if length(btrim(p_data->>'patient_name')) not between 1 and 150 or length(btrim(p_data->>'species')) not between 1 and 120 then raise exception 'patient_required';end if;
 elsif p_action='appointment_state' then
 v_id=(p_data->>'id')::uuid;
 select * into v_appointment from public.clinic_appointments where id=v_id and clinic_id=p_clinic for update;
 if not found or not (v_appointment.professional_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin','mvz','auxiliar','recepcion'])) then raise exception 'access_denied';end if;
 if v_appointment.version<>(p_data->>'version')::int then raise exception 'version_conflict';end if;
 if v_appointment.state in ('cancelado','entregado') then raise exception 'appointment_closed';end if;
 if not ((v_appointment.state='agendado' and p_data->>'state' in ('en_atencion','cancelado')) or (v_appointment.state='en_atencion' and p_data->>'state' in ('listo','cancelado')) or (v_appointment.state='listo' and p_data->>'state'='entregado')) then raise exception 'invalid_transition';end if;
 update public.clinic_appointments set state=p_data->>'state',version=version+1 where id=v_id;
 elsif p_action='task' then
 insert into public.clinic_tasks(clinic_id,title,assigned_to,priority,created_by) values(p_clinic,p_data->>'title',nullif(p_data->>'assigned_to','')::uuid,p_data->>'priority',auth.uid()) returning id into v_id;
 elsif p_action='task_complete' then
 v_id=(p_data->>'id')::uuid;
 update public.clinic_tasks set completed_at=clock_timestamp(),completed_by=auth.uid() where id=v_id and clinic_id=p_clinic and completed_at is null and (assigned_to=auth.uid() or assigned_to is null or created_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']));
 if not found then raise exception 'access_denied';end if;
 elsif p_action='message' then
 insert into public.clinic_messages(clinic_id,category,body,author_id) values(p_clinic,p_data->>'category',p_data->>'body',auth.uid()) returning id into v_id;
 elsif p_action='supplier' then
 if not private.has_clinic_role(p_clinic,array['admin','recepcion']) then raise exception 'access_denied';end if;
 insert into public.clinic_suppliers(clinic_id,name,phone,notes,created_by) values(p_clinic,p_data->>'name',coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 elsif p_action='service_act' then
 select * into v_service from public.clinic_services where id=(p_data->>'service_id')::uuid and clinic_id=p_clinic and active for share;
 if not found then raise exception 'service_required';end if;
 v_prof=(p_data->>'professional_id')::uuid;
 if not (v_prof=auth.uid() or private.has_clinic_role(p_clinic,array['admin','recepcion'])) then raise exception 'access_denied';end if;
 if nullif(p_data->>'appointment_id','') is not null and not exists(select 1 from public.clinic_appointments where id=(p_data->>'appointment_id')::uuid and clinic_id=p_clinic and professional_id=v_prof) then raise exception 'invalid_appointment';end if;
 insert into public.clinic_service_acts(clinic_id,service_id,professional_id,appointment_id,name,service_version,price,commission,commission_kind,commission_value,created_by) values(p_clinic,v_service.id,v_prof,nullif(p_data->>'appointment_id','')::uuid,v_service.name,v_service.version,v_service.price,case when v_service.commission_kind='porcentaje' then round(v_service.price*v_service.commission_value/100,2) else v_service.commission_value end,v_service.commission_kind,v_service.commission_value,auth.uid()) returning id into v_id;
 else raise exception 'unknown_operation';end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'ops_'||p_action,v_id::text);
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 return v_id;
end$$;
create function public.ops_medical(p_clinic uuid,p_details jsonb default null,p_consent boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic) then raise exception 'access_denied';end if;
 if p_details is not null then
 if not p_consent then raise exception 'consent_required';end if;
 if p_details='{}'::jsonb then delete from public.staff_medical_profiles where clinic_id=p_clinic and user_id=auth.uid();
 else insert into public.staff_medical_profiles(clinic_id,user_id,details) values(p_clinic,auth.uid(),p_details) on conflict(clinic_id,user_id) do update set details=excluded.details,updated_at=clock_timestamp();end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'staff_medical_updated',auth.uid()::text);
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.staff_medical_profiles m where clinic_id=p_clinic and (user_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin'])));
end$$;
alter table public.inventory_sale_lines add column service_act_id uuid,add constraint sale_service_act_clinic foreign key(clinic_id,service_act_id) references public.clinic_service_acts(clinic_id,id);
revoke all on function public.ops_dashboard(uuid),public.ops_write(uuid,text,jsonb,text),public.ops_medical(uuid,jsonb,boolean) from public,anon;
grant execute on function public.ops_dashboard(uuid),public.ops_write(uuid,text,jsonb,text),public.ops_medical(uuid,jsonb,boolean) to authenticated;
create or replace function public.inv_sale_post(p_shift uuid,p_method text,p_lines jsonb,p_expected_total text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;i public.inventario;l public.lotes_inventario;x jsonb;v_sale uuid;fp jsonb;n numeric;total numeric=0;cost numeric=0;commission numeric=0;line_total numeric;line_cost numeric;line_commission numeric;meta jsonb;name text;price numeric;prof uuid;rx uuid;v_item uuid;charge public.inventory_application_charges;delivery public.inventory_delivery_tickets;act public.clinic_service_acts;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 if not found or sh.cashier_id<>auth.uid() or not private.inv_access(sh.clinic_id) then raise exception 'own_shift_required';end if;
 fp=jsonb_build_object('kind','sale','shift',p_shift,'method',p_method,'lines',p_lines,'total',p_expected_total);v_sale=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_sale is not null then return v_sale;end if;
 if sh.closed_at is not null then raise exception 'closed_shift';end if;
 if p_method not in ('efectivo','tarjeta','transferencia') or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 50 then raise exception 'sale_lines_required';end if;
 -- Deterministic locks avoid overselling across cashiers and multi-item deadlocks.
 for v_item in select distinct (e->>'service_act_id')::uuid from jsonb_array_elements(p_lines) e where nullif(e->>'service_act_id','') is not null order by 1 loop perform 1 from public.clinic_service_acts where id=v_item and clinic_id=sh.clinic_id for update;end loop;
 for v_item in select distinct (e->>'item_id')::uuid from jsonb_array_elements(p_lines) e where e->>'kind'='producto' order by 1 loop
  perform 1 from public.inventario where id=v_item and clinic_id=sh.clinic_id for update;
 end loop;
 for v_item in select distinct (e->>'lot_id')::uuid from jsonb_array_elements(p_lines) e where e->>'kind'='producto' order by 1 loop
  perform 1 from public.lotes_inventario where id=v_item and clinic_id=sh.clinic_id for update;
 end loop;
 for v_item in select distinct (e->>'charge_id')::uuid from jsonb_array_elements(p_lines) e where nullif(e->>'charge_id','') is not null order by 1 loop perform 1 from public.inventory_application_charges where id=v_item and clinic_id=sh.clinic_id for update;end loop;
 for v_item in select distinct (e->>'delivery_id')::uuid from jsonb_array_elements(p_lines) e where nullif(e->>'delivery_id','') is not null order by 1 loop perform 1 from public.inventory_delivery_tickets where id=v_item and clinic_id=sh.clinic_id for update;end loop;
 v_sale=gen_random_uuid();
 for x in select * from jsonb_array_elements(p_lines) loop
  n=private.inv_quantity(x->>'quantity');meta='{}';prof=null;rx=null;charge=null;delivery=null;act=null;
  if x->>'kind'='producto' then
   select * into i from public.inventario where id=(x->>'item_id')::uuid and clinic_id=sh.clinic_id;
   select * into l from public.lotes_inventario where id=(x->>'lot_id')::uuid and clinic_id=sh.clinic_id and item_id=i.id;
   if i.id is null or l.id is null or not i.m8_enabled or not i.active then raise exception 'enabled_product_lot_required';end if;
   if (i.m8_kind='farmaco' and l.caducidad is null) or (l.caducidad is not null and l.caducidad<=(clock_timestamp() at time zone sh.timezone)::date) then raise exception 'expired_lot_blocked';end if;
   if n>l.cantidad or n>i.stock then raise exception 'insufficient_stock';end if;
   if i.stock_unit in ('unidad','frasco','caja') and n<>trunc(n) then raise exception 'whole_package_required';end if;
   if private.inv_money(x->>'price')<>i.precio_venta then raise exception 'sale_price_changed';end if;
   rx=nullif(x->>'prescription_item_id','')::uuid;meta=private.inv_dispense(i,rx,n)||jsonb_build_object('unit_cost',l.costo_unitario::text);
   name=i.nombre;price=i.precio_venta;line_cost=round(l.costo_unitario*n,2);line_commission=0;
   update public.lotes_inventario set cantidad=cantidad-n where id=l.id;
   update public.inventario set stock=stock-n,version=version+1 where id=i.id;
   insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,source_id,created_by) values(sh.clinic_id,i.id,l.id,-n,'venta',l.costo_unitario,'Venta registrada',v_sale,auth.uid());
  elsif x->>'kind'='servicio' and nullif(x->>'delivery_id','') is not null then
   select * into delivery from public.inventory_delivery_tickets where id=(x->>'delivery_id')::uuid and clinic_id=sh.clinic_id;
   if delivery.id is null or n<>1 or private.inv_money(x->>'price')<>delivery.price then raise exception 'delivery_charge_mismatch';end if;
   if exists(select 1 from public.inventory_sale_lines sl where sl.delivery_ticket_id=delivery.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id)) then raise exception 'delivery_already_paid';end if;
   name=delivery.name;price=delivery.price;line_cost=delivery.cost;line_commission=0;
   meta=jsonb_build_object('billing_only',true,'delivery_reference',delivery.reference);
  elsif x->>'kind'='servicio' and nullif(x->>'charge_id','') is not null then
   select * into charge from public.inventory_application_charges where id=(x->>'charge_id')::uuid and clinic_id=sh.clinic_id;
   if charge.id is null or n<>1 or private.inv_money(x->>'price')<>charge.price then raise exception 'application_charge_mismatch';end if;
   if exists(select 1 from public.inventory_sale_lines sl where sl.application_charge_id=charge.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id)) then raise exception 'application_already_paid';end if;
   name=charge.name;price=charge.price;line_cost=charge.cost;line_commission=0;
   meta=jsonb_build_object('billing_only',true,'clinical_reference',charge.reference,'cost_pending',charge.cost_pending);
  elsif x->>'kind'='servicio' and nullif(x->>'service_act_id','') is not null then
   select * into act from public.clinic_service_acts where id=(x->>'service_act_id')::uuid and clinic_id=sh.clinic_id;
   if act.id is null or n<>1 or private.inv_money(x->>'price')<>act.price then raise exception 'service_act_mismatch';end if;
   if exists(select 1 from public.inventory_sale_lines sl where sl.service_act_id=act.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id)) then raise exception 'service_already_paid';end if;
   name=act.name;price=act.price;line_cost=0;line_commission=act.commission;prof=act.professional_id;
   meta=jsonb_build_object('billing_only',true,'service_version',act.service_version,'commission_kind',act.commission_kind,'commission_value',act.commission_value::text,'performed_by',act.professional_id,'performed_at',act.created_at,'cost_pending',true);
  elsif x->>'kind'='servicio' then
   if not private.has_clinic_role(sh.clinic_id,array['admin']) then raise exception 'service_capture_admin_until_m9';end if;
   name=btrim(x->>'name');if coalesce(length(name),0) not between 1 and 200 then raise exception 'service_name_required';end if;
   price=private.inv_money(x->>'price');line_cost=private.inv_money(x->>'cost');line_commission=private.inv_money(x->>'commission');
   prof=nullif(x->>'professional_id','')::uuid;
   if prof is not null and not exists(select 1 from public.clinic_members where clinic_id=sh.clinic_id and user_id=prof) then raise exception 'service_professional_wrong_clinic';end if;
   if line_commission>0 and prof is null then raise exception 'commission_professional_required';end if;
   meta=jsonb_build_object('service_catalog','captura manual pendiente M9','commission_basis','Importe total capturado por admin');
  else raise exception 'sale_line_kind_required';end if;
  line_total=round(price*n,2);if line_commission>line_total then raise exception 'commission_exceeds_service_total';end if;
  total=total+line_total;cost=cost+line_cost;commission=commission+line_commission;
  insert into public.inventory_sale_lines(sale_id,clinic_id,kind,item_id,lot_id,prescription_item_id,name,lot,quantity,stock_unit,price,cost,total,commission,professional_id,metadata,application_charge_id,delivery_ticket_id,service_act_id)
  values(v_sale,sh.clinic_id,x->>'kind',case when x->>'kind'='producto' then i.id end,case when x->>'kind'='producto' then l.id end,rx,name,case when x->>'kind'='producto' then l.lote end,n,case when x->>'kind'='producto' then i.stock_unit else 'servicio' end,price,line_cost,line_total,line_commission,prof,meta,charge.id,delivery.id,act.id);
 end loop;
 if total<=0 or total<>private.inv_money(p_expected_total) then raise exception 'sale_total_changed';end if;
 insert into public.inventory_sales(id,clinic_id,shift_id,cashier_id,method,total,cost,commission) values(v_sale,sh.clinic_id,sh.id,auth.uid(),p_method,total,cost,commission);
 insert into private.vet_operation_receipts values(auth.uid(),sh.clinic_id,p_operation,fp,v_sale);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(sh.clinic_id,auth.uid(),'inventory_sale_posted',v_sale);return v_sale;
end $$;


commit;

notify pgrst, 'reload schema';
select '05C COMPLETADO: agenda, servicios y equipo' as resultado;
-- FIN COMPLETO 05C
