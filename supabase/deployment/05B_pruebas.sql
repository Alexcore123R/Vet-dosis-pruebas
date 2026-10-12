-- SOLO proyecto de pruebas wtrelwtztkddfktrfdpb. Ejecutar 05A, 05B, 05C en orden.
-- Sin datos clínicos, productos ni precios de ejemplo.
-- Additive correction: delivery is not collection; an application is not a whole bottle sale.
-- Apply once AFTER existing_inventory_m8.sql. No clinical/legal examples seeded.
begin;
create table public.inventory_delivery_grants(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),responsible_id uuid not null references auth.users(id),
 recipient_id uuid not null references auth.users(id),valid_until timestamptz,reason text not null,created_at timestamptz not null default clock_timestamp());
create table public.inventory_delivery_revocations(
 id uuid primary key default gen_random_uuid(),grant_id uuid not null unique references public.inventory_delivery_grants(id),
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create table public.inventory_application_tariffs(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),product_version_id uuid not null references public.medication_product_versions(id),
 price numeric(18,2) not null check(price>=0),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create table public.inventory_application_charges(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),medication_record_id uuid not null,
 root_record_id uuid not null unique,tariff_id uuid not null references public.inventory_application_tariffs(id),
 name text not null,price numeric(18,2) not null,cost numeric(18,2) not null,cost_pending boolean not null,
 reference jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),
 foreign key(clinic_id,medication_record_id) references public.medication_records(clinic_id,id),foreign key(clinic_id,root_record_id) references public.medication_records(clinic_id,id));
create table public.inventory_delivery_tickets(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,item_id uuid not null,lot_id uuid not null,prescription_item_id uuid not null references public.prescription_items(id),
 quantity numeric(24,9) not null,name text not null,price numeric(18,2) not null,cost numeric(18,2) not null,reference jsonb not null,
 delivered_by uuid not null references auth.users(id),delivered_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),
 foreign key(clinic_id,item_id) references public.inventario(clinic_id,id),foreign key(clinic_id,lot_id) references public.lotes_inventario(clinic_id,id));
alter table public.inventory_sale_lines add column application_charge_id uuid,
 add column delivery_ticket_id uuid,
 add constraint inv_delivery_ticket_same_clinic foreign key(clinic_id,delivery_ticket_id) references public.inventory_delivery_tickets(clinic_id,id),
 add constraint inv_application_charge_same_clinic foreign key(clinic_id,application_charge_id) references public.inventory_application_charges(clinic_id,id);
do $$declare t text;begin
 foreach t in array array['inventory_delivery_grants','inventory_application_tariffs','inventory_application_charges','inventory_delivery_tickets'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 execute format('create policy inv_workflow_read on public.%I for select to authenticated using(private.inv_access(clinic_id))',t);
 execute format('create trigger inv_workflow_history before update or delete on public.%I for each row execute function private.inv_history_guard()',t);
 end loop;
end $$;
alter table public.inventory_delivery_revocations enable row level security;
revoke all on public.inventory_delivery_revocations from anon,authenticated;grant select on public.inventory_delivery_revocations to authenticated;
create policy inv_delivery_revocation_read on public.inventory_delivery_revocations for select to authenticated using(exists(select 1 from public.inventory_delivery_grants g where g.id=grant_id and private.inv_access(g.clinic_id)));
create trigger inv_delivery_revoke_history before update or delete on public.inventory_delivery_revocations for each row execute function private.inv_history_guard();
create function public.inv_delivery_grant(p_clinic uuid,p_recipient uuid,p_until timestamptz,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;
begin
 if not private.rx_professional(p_clinic,auth.uid()) then raise exception 'responsible_professional_only';end if;
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=p_recipient and role in ('auxiliar','recepcion')) or p_recipient=auth.uid() then raise exception 'delivery_recipient_required';end if;
 if p_until is not null and p_until<=clock_timestamp() or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'delivery_grant_fields_required';end if;
 fp=jsonb_build_object('kind','delivery_grant','recipient',p_recipient,'until',p_until,'reason',p_reason);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_delivery_grants(clinic_id,responsible_id,recipient_id,valid_until,reason) values(p_clinic,auth.uid(),p_recipient,p_until,p_reason) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'ordinary_delivery_permission_granted',v_id);return v_id;
end $$;
create function public.inv_delivery_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare g public.inventory_delivery_grants;v_id uuid;fp jsonb;
begin
 perform 1 from public.professional_profiles p join public.inventory_delivery_grants dg on dg.clinic_id=p.clinic_id and dg.responsible_id=p.user_id where dg.id=p_id for update of p;
 select * into g from public.inventory_delivery_grants where id=p_id for update;
 if not found or g.responsible_id<>auth.uid() or not private.rx_professional(g.clinic_id,auth.uid()) then raise exception 'responsible_professional_only';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'reason_required';end if;
 fp=jsonb_build_object('kind','delivery_revoke','grant',p_id,'reason',p_reason);v_id=private.vet_receipt(g.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_delivery_revocations(grant_id,reason,created_by) values(g.id,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),g.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(g.clinic_id,auth.uid(),'ordinary_delivery_permission_revoked',v_id);return v_id;
end $$;
create function public.inv_application_tariff(p_clinic uuid,p_product uuid,p_price text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;n numeric;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'inventory_admin_required';end if;
 if not exists(select 1 from public.medication_product_versions where id=p_product) then raise exception 'product_version_required';end if;
 n=private.inv_money(p_price);fp=jsonb_build_object('kind','application_tariff','product',p_product,'price',p_price);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_application_tariffs(clinic_id,product_version_id,price,created_by) values(p_clinic,p_product,n,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end $$;
create function public.inv_application_prepare(p_record uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.medication_records;c public.clinical_cases;p public.medication_product_versions;rx public.prescriptions;t public.inventory_application_tariffs;v public.medication_vials;l public.lotes_inventario;link public.inventory_vial_links;root uuid;v_id uuid;fp jsonb;cost numeric=0;pending boolean=true;
begin
 select * into r from public.medication_records where id=p_record for update;
 select * into c from public.clinical_cases where id=r.case_id;
 if r.id is null or not private.rx_case(c) or not private.has_clinic_role(r.clinic_id,array['admin','mvz','auxiliar']) then raise exception 'clinical_case_access_required';end if;
 select * into p from public.medication_product_versions where id=r.product_version_id;
 select * into rx from public.prescriptions where id=r.prescription_id and clinic_id=r.clinic_id and state='issued';
 if p.id is null or not private.rx_product_verified(p) or rx.id is null or not exists(select 1 from public.prescription_items where prescription_id=rx.id and product_version_id=p.id) then raise exception 'issued_matching_prescription_required';end if;
 if exists(select 1 from public.medication_records where replaces_id=r.id) then raise exception 'use_current_application_record';end if;
 with recursive chain as (select id,replaces_id from public.medication_records where id=r.id union all select m.id,m.replaces_id from public.medication_records m join chain a on m.id=a.replaces_id) select id into root from chain where replaces_id is null;
 perform pg_advisory_xact_lock(hashtextextended('application-charge-'||root::text,0));
 fp=jsonb_build_object('kind','application_charge','record',r.id);v_id=private.vet_receipt(r.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 select * into t from public.inventory_application_tariffs where clinic_id=r.clinic_id and product_version_id=p.id order by created_at desc,id desc limit 1;
 if t.id is null or t.price<=0 then raise exception 'application_tariff_required';end if;
 select * into v from public.medication_vials where id=r.vial_id;
 select * into link from public.inventory_vial_links where vial_id=v.id;
 select * into l from public.lotes_inventario where id=link.lot_id;
 if link.id is not null and v.initial_volume>0 and r.unit='ml' then cost=round(l.costo_unitario*link.packages*r.quantity/v.initial_volume,2);pending=false;end if;
 insert into public.inventory_application_charges(clinic_id,medication_record_id,root_record_id,tariff_id,name,price,cost,cost_pending,reference,created_by)
 values(r.clinic_id,r.id,root,t.id,'Aplicación: '||p.name||' · '||r.quantity::text||' '||r.unit,t.price,cost,pending,
 jsonb_build_object('prescription_id',rx.id,'medication_record_id',r.id,'patient_name',(select name from public.vet_patients where id=r.patient_id),'quantity',r.quantity::text,'unit',r.unit,'performed_by',r.performed_by,'observed_at',r.observed_at,'reported_at',r.reported_at,'validation','El cobro no valida el acto clínico; consultar revisión en expediente','content_hash',r.content_hash,'cost_pending',pending),auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),r.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(r.clinic_id,auth.uid(),'application_charge_prepared',v_id);return v_id;
end $$;
create function public.inv_workflow_dashboard(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.inv_access(p_clinic) then raise exception 'inventory_access_required';end if;
 return jsonb_build_object('deliveries',coalesce((select jsonb_agg(to_jsonb(dt)||jsonb_build_object('price',dt.price::text,'cost',dt.cost::text,'paid',exists(select 1 from public.inventory_sale_lines sl where sl.delivery_ticket_id=dt.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id)))) from public.inventory_delivery_tickets dt where clinic_id=p_clinic),'[]'),'charges',coalesce((select jsonb_agg(to_jsonb(ch)||jsonb_build_object('price',ch.price::text,'cost',ch.cost::text,'paid',exists(select 1 from public.inventory_sale_lines sl where sl.application_charge_id=ch.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id))) order by ch.created_at desc) from public.inventory_application_charges ch where clinic_id=p_clinic),'[]'),
 'applications',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',p.name,'quantity',r.quantity::text,'unit',r.unit,'observed_at',r.observed_at,'prescription_id',r.prescription_id)) from public.medication_records r join public.clinical_cases c on c.id=r.case_id join public.medication_product_versions p on p.id=r.product_version_id where r.clinic_id=p_clinic and private.rx_case(c) and r.prescription_id is not null and not exists(select 1 from public.medication_records n where n.replaces_id=r.id)),'[]'),
 'grants',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('revoked',exists(select 1 from public.inventory_delivery_revocations rv where rv.grant_id=g.id))) from public.inventory_delivery_grants g where g.clinic_id=p_clinic and (g.responsible_id=auth.uid() or g.recipient_id=auth.uid())),'[]'));
end $$;
create or replace function private.inv_dispense(i public.inventario,p_rx uuid,p_quantity numeric) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.medication_product_versions;r public.prescriptions;x public.prescription_items;c public.clinical_cases;profile public.professional_profiles;delegation public.professional_delegations;v_limit public.inventory_dispensing_limits;dispensed numeric;
begin
 if i.m8_kind='producto' then if p_rx is not null then raise exception 'non_medication_prescription_denied';end if;return '{}'::jsonb;end if;
 select * into p from public.medication_product_versions where id=i.medication_version_id;
 if p.id is null or not private.rx_product_verified(p) then raise exception 'verified_medication_reference_required';end if;
 select * into x from public.prescription_items where id=p_rx;
 select * into r from public.prescriptions where id=x.prescription_id and clinic_id=i.clinic_id and state='issued';
 if r.id is null or x.product_version_id<>p.id then raise exception 'issued_matching_prescription_required';end if;
 select * into c from public.clinical_cases where id=r.case_id;
 if p.classification<>'no_controlado' or p.quantified_prescription then
  if not private.rx_professional(i.clinic_id,auth.uid()) then raise exception 'quantified_dispensing_professional_only';end if;
  if coalesce(length(btrim(r.official_folio)),0)=0 then raise exception 'captured_official_folio_required';end if;
 else
  if not private.rx_professional(i.clinic_id,auth.uid()) then
   if not private.has_clinic_role(i.clinic_id,array['auxiliar','recepcion']) then raise exception 'ordinary_dispensing_delegation_required';end if;
   select * into profile from public.professional_profiles where clinic_id=i.clinic_id and user_id=c.responsible_id for update;
   select * into delegation from public.professional_delegations d where d.profile_id=profile.id and d.recipient_id=auth.uid() and d.case_id=c.id and d.dispense_ordinary and d.valid_until>clock_timestamp() and not exists(select 1 from public.professional_delegation_revocations z where z.delegation_id=d.id) order by d.created_at desc limit 1;
   if (delegation.id is null or not private.rx_case(c)) and not exists(select 1 from public.inventory_delivery_grants g where g.clinic_id=i.clinic_id and g.responsible_id=c.responsible_id and g.recipient_id=auth.uid() and (g.valid_until is null or g.valid_until>clock_timestamp()) and not exists(select 1 from public.inventory_delivery_revocations z where z.grant_id=g.id)) then raise exception 'ordinary_dispensing_delegation_required';end if;
   if not private.rx_professional(i.clinic_id,c.responsible_id) then raise exception 'ordinary_dispensing_delegation_required';end if;
  end if;
 end if;
 select * into v_limit from public.inventory_dispensing_limits where item_id=i.id and prescription_item_id=x.id order by created_at desc,id desc limit 1;
 if v_limit.id is null or v_limit.valid_until<=clock_timestamp() or v_limit.quantity<=0 then raise exception 'dispensing_quantity_authorization_required';end if;
 select coalesce(sum(sl.quantity),0) into dispensed from public.inventory_sale_lines sl where sl.item_id=i.id and sl.prescription_item_id=x.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id);
 select dispensed+coalesce(sum(dt.quantity),0) into dispensed from public.inventory_delivery_tickets dt where dt.item_id=i.id and dt.prescription_item_id=x.id;
 if dispensed+p_quantity>v_limit.quantity then raise exception 'dispensing_authorized_quantity_exceeded';end if;
 return jsonb_build_object('quantity_authorization_id',v_limit.id,'medication_version_id',p.id,'classification',p.classification,'quantified',p.quantified_prescription,'prescription_id',r.id,'folio',r.official_folio,'dispensed_by',auth.uid(),'delegation_id',delegation.id);
end $$;
create or replace function public.inv_sale_post(p_shift uuid,p_method text,p_lines jsonb,p_expected_total text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;i public.inventario;l public.lotes_inventario;x jsonb;v_sale uuid;fp jsonb;n numeric;total numeric=0;cost numeric=0;commission numeric=0;line_total numeric;line_cost numeric;line_commission numeric;meta jsonb;name text;price numeric;prof uuid;rx uuid;v_item uuid;charge public.inventory_application_charges;delivery public.inventory_delivery_tickets;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 if not found or sh.cashier_id<>auth.uid() or not private.inv_access(sh.clinic_id) then raise exception 'own_shift_required';end if;
 fp=jsonb_build_object('kind','sale','shift',p_shift,'method',p_method,'lines',p_lines,'total',p_expected_total);v_sale=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_sale is not null then return v_sale;end if;
 if sh.closed_at is not null then raise exception 'closed_shift';end if;
 if p_method not in ('efectivo','tarjeta','transferencia') or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 50 then raise exception 'sale_lines_required';end if;
 -- Deterministic locks avoid overselling across cashiers and multi-item deadlocks.
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
  n=private.inv_quantity(x->>'quantity');meta='{}';prof=null;rx=null;charge=null;delivery=null;
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
  insert into public.inventory_sale_lines(sale_id,clinic_id,kind,item_id,lot_id,prescription_item_id,name,lot,quantity,stock_unit,price,cost,total,commission,professional_id,metadata,application_charge_id,delivery_ticket_id)
  values(v_sale,sh.clinic_id,x->>'kind',case when x->>'kind'='producto' then i.id end,case when x->>'kind'='producto' then l.id end,rx,name,case when x->>'kind'='producto' then l.lote end,n,case when x->>'kind'='producto' then i.stock_unit else 'servicio' end,price,line_cost,line_total,line_commission,prof,meta,charge.id,delivery.id);
 end loop;
 if total<=0 or total<>private.inv_money(p_expected_total) then raise exception 'sale_total_changed';end if;
 insert into public.inventory_sales(id,clinic_id,shift_id,cashier_id,method,total,cost,commission) values(v_sale,sh.clinic_id,sh.id,auth.uid(),p_method,total,cost,commission);
 insert into private.vet_operation_receipts values(auth.uid(),sh.clinic_id,p_operation,fp,v_sale);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(sh.clinic_id,auth.uid(),'inventory_sale_posted',v_sale);return v_sale;
end $$;

create function public.inv_delivery_items(p_clinic uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'product_version_id',x.product_version_id,'prescription_id',r.id,'folio',r.official_folio)), '[]')
 from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id
 where r.clinic_id=$1 and private.inv_access($1) and r.state='issued' and not r.controlled and exists(
 select 1 from public.inventory_delivery_grants g where g.clinic_id=$1 and g.responsible_id=r.responsible_id and g.recipient_id=auth.uid() and (g.valid_until is null or g.valid_until>clock_timestamp()) and private.rx_professional(g.clinic_id,g.responsible_id) and not exists(select 1 from public.inventory_delivery_revocations z where z.grant_id=g.id));
$$;
create function public.inv_delivery_prepare(p_lot uuid,p_rx uuid,p_quantity text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;reference jsonb;
begin
 select * into l from public.lotes_inventario where id=p_lot;
 select * into i from public.inventario where id=l.item_id for update;
 select * into l from public.lotes_inventario where id=p_lot for update;
 if i.id is null or not private.inv_access(i.clinic_id) or not i.m8_enabled or not i.active or i.m8_kind<>'farmaco' then raise exception 'enabled_product_lot_required';end if;
 n=private.inv_quantity(p_quantity);fp=jsonb_build_object('kind','physical_delivery','lot',p_lot,'rx',p_rx,'quantity',p_quantity);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if l.caducidad is null or l.caducidad<=(clock_timestamp() at time zone private.inv_timezone(i.clinic_id))::date then raise exception 'expired_lot_blocked';end if;
 if l.cantidad<n or i.stock<n then raise exception 'insufficient_stock';end if;
 if i.stock_unit in ('unidad','frasco','caja') and n<>trunc(n) then raise exception 'whole_package_required';end if;
 reference=private.inv_dispense(i,p_rx,n)||jsonb_build_object('quantity',n::text,'stock_unit',i.stock_unit,'lot',l.lote,'unit_cost',l.costo_unitario::text);
 insert into public.inventory_delivery_tickets(clinic_id,item_id,lot_id,prescription_item_id,quantity,name,price,cost,reference,delivered_by)
 values(i.clinic_id,i.id,l.id,p_rx,n,'Entrega: '||i.nombre||' · '||n::text||' '||i.stock_unit,round(i.precio_venta*n,2),round(l.costo_unitario*n,2),reference,auth.uid()) returning id into v_id;
 update public.lotes_inventario set cantidad=cantidad-n where id=l.id;
 update public.inventario set stock=stock-n,version=version+1 where id=i.id;
 insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,source_id,created_by) values(i.clinic_id,i.id,l.id,-n,'venta',l.costo_unitario,'Entrega clínica; cobro separado',v_id,auth.uid());
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'medication_delivered_payment_separate',v_id);return v_id;
end $$;
revoke all on function public.inv_delivery_prepare(uuid,uuid,text,text) from public,anon;grant execute on function public.inv_delivery_prepare(uuid,uuid,text,text) to authenticated;
revoke all on function public.inv_delivery_grant(uuid,uuid,timestamptz,text,text),public.inv_delivery_revoke(uuid,text,text),public.inv_application_tariff(uuid,uuid,text,text),public.inv_application_prepare(uuid,text),public.inv_workflow_dashboard(uuid),public.inv_delivery_items(uuid) from public,anon;
grant execute on function public.inv_delivery_grant(uuid,uuid,timestamptz,text,text),public.inv_delivery_revoke(uuid,text,text),public.inv_application_tariff(uuid,uuid,text,text),public.inv_application_prepare(uuid,text),public.inv_workflow_dashboard(uuid),public.inv_delivery_items(uuid) to authenticated;
commit;

notify pgrst, 'reload schema';
select '05B COMPLETADO: entregas y cobros de tratamientos' as resultado;
-- FIN COMPLETO 05B
