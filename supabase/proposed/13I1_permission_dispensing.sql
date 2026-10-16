-- LOCAL CANDIDATE 13I1, after 13H3. Physical dispensing is not collection.
-- No deployment or beta activation. Remaining inventory/cash management cut is separate.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
alter table public.inventory_dispensing_limits
 add column permission_grant_id uuid references private.member_permission_grants(id),
 add column member_since timestamptz,
 add column profile_version_id uuid references private.professional_profile_versions(id),
 add constraint dispensing_authority_metadata check(
 (permission_grant_id is null and member_since is null and profile_version_id is null) or
 (permission_grant_id is not null and member_since is not null and profile_version_id is not null));
-- Legacy quantities retain NULL authority; no automatic reuse or role conversion.
create function private.dispensing_access(clinic uuid,person uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.clinical_professional_at(clinic,person,clock_timestamp()) and
 exists(select 1 from private.member_permission_grants where id=private.permission_effective(clinic,person,'controlled.dispense') and valid_until>clock_timestamp()) and
 exists(select 1 from private.member_permission_grants where id=private.permission_effective(clinic,person,'inventory.read') and valid_until>clock_timestamp()) and
 exists(select 1 from private.member_permission_grants where id=private.permission_effective(clinic,person,'patient.read') and valid_until>clock_timestamp()) and
 exists(select 1 from private.member_permission_grants where id=private.permission_effective(clinic,person,'clinical.read') and valid_until>clock_timestamp());
$$;
create function private.dispensing_require(clinic uuid) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9061));
 if not private.dispensing_access(clinic,auth.uid()) then raise exception 'verified_dispensing_permission_required';end if;
 return private.permission_effective(clinic,auth.uid(),'controlled.dispense');
end$$;
create function public.inv_dispensing_permissions(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if private.permission_effective(p_clinic,auth.uid(),'inventory.read') is null then raise exception 'inventory_read_permission_required';end if;
 return jsonb_build_object('schema_version',1,'mode','verified_dispensing','can_dispense',private.dispensing_access(p_clinic,auth.uid()),'can_authorize',private.dispensing_access(p_clinic,auth.uid()),'legacy_delivery_grants',false);
end$$;
create or replace function public.inv_dispensing_authorize(p_item uuid,p_rx uuid,p_quantity text,p_until timestamptz,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;r public.prescriptions;x public.prescription_items;v_id uuid;fp jsonb;n numeric;g uuid;epoch timestamptz;pv uuid;
begin
 select * into i from public.inventario where id=p_item;
 if not found then raise exception 'dispensing_limit_responsible_required';end if;
 perform private.medication_lock(i.clinic_id);
 g=private.dispensing_require(i.clinic_id);
 select * into i from public.inventario where id=p_item for update;
 select * into x from public.prescription_items where id=p_rx;
 select * into r from public.prescriptions where id=x.prescription_id and clinic_id=i.clinic_id and state='issued';
 if i.id is null or i.m8_kind<>'farmaco' or i.medication_version_id<>x.product_version_id or r.id is null or r.responsible_id<>auth.uid() or not private.dispensing_access(i.clinic_id,auth.uid()) then raise exception 'dispensing_limit_responsible_required';end if;
 if not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 select created_at into epoch from public.clinic_members where clinic_id=i.clinic_id and user_id=auth.uid();
 select (private.rx_profile(id)->>'id')::uuid into pv from public.professional_profiles where clinic_id=i.clinic_id and user_id=auth.uid();
 n=private.inv_quantity(p_quantity,true);
 if p_until is null or p_until<=clock_timestamp() or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'dispensing_limit_fields_required';end if;
 fp=jsonb_build_object('kind','dispensing_limit','item',p_item,'rx',p_rx,'quantity',p_quantity,'until',p_until,'reason',p_reason);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_dispensing_limits(clinic_id,item_id,prescription_item_id,quantity,valid_until,reason,created_by,permission_grant_id,member_since,profile_version_id) values(i.clinic_id,i.id,x.id,n,p_until,p_reason,auth.uid(),g,epoch,pv) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_dispensing_limit_authorized',v_id);return v_id;
end $$;
create or replace function private.inv_dispense(i public.inventario,p_rx uuid,p_quantity numeric) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.medication_product_versions;r public.prescriptions;x public.prescription_items;lim public.inventory_dispensing_limits;used numeric;g uuid;person uuid;begin
 if i.m8_kind='producto' then if p_rx is not null then raise exception 'non_medication_prescription_denied';end if;return '{}'::jsonb;end if;
 select * into x from public.prescription_items where id=p_rx;
 select * into r from public.prescriptions where id=x.prescription_id and clinic_id=i.clinic_id and state='issued';
 for person in select distinct actor_id from unnest(array[auth.uid(),r.responsible_id]) actors(actor_id) where actor_id is not null order by actor_id loop
 perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 g=private.dispensing_require(i.clinic_id);
 select * into p from public.medication_product_versions where id=i.medication_version_id;
 if p.id is null or not private.rx_product_verified(p) then raise exception 'verified_medication_reference_required';end if;
 select * into x from public.prescription_items where id=p_rx;
 select * into r from public.prescriptions where id=x.prescription_id and clinic_id=i.clinic_id and state='issued';
 if r.id is null or x.product_version_id<>p.id then raise exception 'issued_matching_prescription_required';end if;
 if not private.rx_readable(r) then raise exception 'prescription_access_denied';end if;
 if (p.classification<>'no_controlado' or p.quantified_prescription) and coalesce(length(btrim(r.official_folio)),0)=0 then raise exception 'captured_official_folio_required';end if;
 select * into lim from public.inventory_dispensing_limits where item_id=i.id and prescription_item_id=x.id order by created_at desc,id desc limit 1;
 if lim.id is null or lim.permission_grant_id is null then raise exception 'dispensing_limit_reauthorization_required';end if;
 if lim.valid_until<=clock_timestamp() or lim.quantity<=0 then raise exception 'dispensing_quantity_authorization_required';end if;
 if lim.created_by<>r.responsible_id or not private.dispensing_access(i.clinic_id,lim.created_by)
 or private.permission_effective(i.clinic_id,lim.created_by,'controlled.dispense') is distinct from lim.permission_grant_id
 or not exists(select 1 from public.clinic_members where clinic_id=i.clinic_id and user_id=lim.created_by and created_at=lim.member_since)
 or not exists(select 1 from public.professional_profiles where clinic_id=i.clinic_id and user_id=lim.created_by and (private.rx_profile(id)->>'id')::uuid=lim.profile_version_id) then raise exception 'dispensing_limit_authority_changed';end if;
 select coalesce(sum(sl.quantity),0) into used from public.inventory_sale_lines sl where sl.item_id=i.id and sl.prescription_item_id=x.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id);
 select used+coalesce(sum(dt.quantity),0) into used from public.inventory_delivery_tickets dt where dt.item_id=i.id and dt.prescription_item_id=x.id;
 if used+p_quantity>lim.quantity then raise exception 'dispensing_authorized_quantity_exceeded';end if;
 return jsonb_build_object('quantity_authorization_id',lim.id,'limit_permission_grant_id',lim.permission_grant_id,'dispense_grant_id',g,'medication_version_id',p.id,'classification',p.classification,'quantified',p.quantified_prescription,'prescription_id',r.id,'folio',r.official_folio,'dispensed_by',auth.uid());
end$$;
create or replace function public.inv_delivery_prepare(p_lot uuid,p_rx uuid,p_quantity text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;reference jsonb;
begin
 select * into l from public.lotes_inventario where id=p_lot;
 if l.id is null then raise exception 'enabled_product_lot_required';end if;
 perform private.medication_lock(l.clinic_id);
 if not private.dispensing_access(l.clinic_id,auth.uid()) then raise exception 'verified_dispensing_permission_required';end if;
 select * into i from public.inventario where id=l.item_id for update;
 select * into l from public.lotes_inventario where id=p_lot for update;
 if i.id is null or not private.dispensing_access(i.clinic_id,auth.uid()) or not i.m8_enabled or not i.active or i.m8_kind<>'farmaco' then raise exception 'enabled_product_lot_required';end if;
 n=private.inv_quantity(p_quantity);fp=jsonb_build_object('kind','physical_delivery','lot',p_lot,'rx',p_rx,'quantity',p_quantity);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then
 perform private.inv_dispense(i,p_rx,0);return v_id;end if;
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
create or replace function public.inv_sale_post(p_shift uuid,p_method text,p_lines jsonb,p_expected_total text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;i public.inventario;l public.lotes_inventario;x jsonb;v_sale uuid;fp jsonb;n numeric;total numeric=0;cost numeric=0;commission numeric=0;line_total numeric;line_cost numeric;line_commission numeric;meta jsonb;name text;price numeric;prof uuid;rx uuid;v_item uuid;charge public.inventory_application_charges;delivery public.inventory_delivery_tickets;act public.clinic_service_acts;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift;
 if not found then raise exception 'own_shift_required';end if;
 perform private.medication_lock(sh.clinic_id);
 -- All stock paths serialize with permission revocations and physical deliveries.
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 if not found or sh.cashier_id<>auth.uid() or not private.inv_access(sh.clinic_id) then raise exception 'own_shift_required';end if;
 fp=jsonb_build_object('kind','sale','shift',p_shift,'method',p_method,'lines',p_lines,'total',p_expected_total);v_sale=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_sale is not null then
 for x in select * from jsonb_array_elements(p_lines) where value->>'kind'='producto' loop
 select * into i from public.inventario where id=(x->>'item_id')::uuid and clinic_id=sh.clinic_id;
 if i.m8_kind='farmaco' then perform private.inv_dispense(i,nullif(x->>'prescription_item_id','')::uuid,0);end if;
 end loop;return v_sale;end if;
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
create or replace function public.inv_sale_reverse(p_sale uuid,p_shift uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.inventory_sales;sh public.inventory_cash_shifts;x public.inventory_sale_lines;v_id uuid;fp jsonb;key uuid;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift;
 if not found then raise exception 'reversal_admin_own_shift_required';end if;
 perform private.medication_lock(sh.clinic_id);
 if exists(select 1 from public.inventory_sale_lines sl join public.inventario i on i.id=sl.item_id where sl.sale_id=p_sale and i.m8_kind='farmaco') then perform private.dispensing_require(sh.clinic_id);end if;
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 select * into s from public.inventory_sales where id=p_sale and clinic_id=sh.clinic_id for update;
 if s.id is null or sh.cashier_id<>auth.uid() or not private.has_clinic_role(sh.clinic_id,array['admin']) then raise exception 'reversal_admin_own_shift_required';end if;
 fp=jsonb_build_object('kind','reverse','sale',p_sale,'shift',p_shift,'reason',p_reason);v_id=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if sh.closed_at is not null then raise exception 'closed_shift';end if;
 if exists(select 1 from public.inventory_sale_reversals where sale_id=s.id) then raise exception 'sale_already_reversed';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'reversal_reason_required';end if;
 if exists(select 1 from public.inventory_sale_lines where sale_id=s.id and (metadata->>'classification'<>'no_controlado' or metadata->>'quantified'='true')) and not private.dispensing_access(sh.clinic_id,auth.uid()) then raise exception 'controlled_reversal_professional_only';end if;
 for key in select distinct item_id from public.inventory_sale_lines where sale_id=s.id and item_id is not null order by 1 loop perform 1 from public.inventario where id=key for update;end loop;
 for key in select distinct lot_id from public.inventory_sale_lines where sale_id=s.id and lot_id is not null order by 1 loop perform 1 from public.lotes_inventario where id=key for update;end loop;
 v_id=gen_random_uuid();
 for x in select * from public.inventory_sale_lines where sale_id=s.id and kind='producto' loop
  update public.lotes_inventario set cantidad=cantidad+x.quantity where id=x.lot_id;
  update public.inventario set stock=stock+x.quantity,version=version+1 where id=x.item_id;
  insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,source_id,created_by) values(sh.clinic_id,x.item_id,x.lot_id,x.quantity,'reverso',(x.metadata->>'unit_cost')::numeric,p_reason,v_id,auth.uid());
 end loop;
 insert into public.inventory_sale_reversals(id,clinic_id,sale_id,shift_id,reason,created_by) values(v_id,sh.clinic_id,s.id,sh.id,p_reason,auth.uid());
 insert into private.vet_operation_receipts values(auth.uid(),sh.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(sh.clinic_id,auth.uid(),'inventory_sale_reversed',v_id);return v_id;
end $$;
-- Legacy grants are history, never authority to dispense under this cut.
create or replace function public.inv_delivery_grant(p_clinic uuid,p_recipient uuid,p_until timestamptz,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$begin
 raise exception 'legacy_delivery_delegation_disabled';end$$;
create or replace function public.inv_delivery_items(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.dispensing_access(p_clinic,auth.uid()) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'product_version_id',x.product_version_id,'prescription_id',r.id,'folio',r.official_folio)) from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.clinic_id=p_clinic and r.state='issued' and private.rx_readable(r)),'[]');
end$$;
create or replace function public.inv_delivery_revoke(p_id uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare g public.inventory_delivery_grants;v_id uuid;fp jsonb;
begin
 select * into g from public.inventory_delivery_grants where id=p_id;
 if not found then raise exception 'responsible_professional_only';end if;
 perform private.medication_lock(g.clinic_id);
 select * into g from public.inventory_delivery_grants where id=p_id for update;
 if not found or g.responsible_id<>auth.uid() or not exists(select 1 from public.clinic_members where clinic_id=g.clinic_id and user_id=auth.uid()) then raise exception 'responsible_professional_only';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'reason_required';end if;
 fp=jsonb_build_object('kind','delivery_revoke','grant',p_id,'reason',p_reason);v_id=private.vet_receipt(g.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_delivery_revocations(grant_id,reason,created_by) values(g.id,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),g.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(g.clinic_id,auth.uid(),'ordinary_delivery_permission_revoked',v_id);return v_id;
end $$;
create or replace function public.inv_stock_adjust(p_lot uuid,p_delta text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;
begin
 select * into l from public.lotes_inventario where id=p_lot;
 if l.id is null then raise exception 'inventory_admin_required';end if;
 perform private.medication_lock(l.clinic_id);
 perform private.hospital_order_permission(l.clinic_id,'inventory.adjust',null,false);
 select * into i from public.inventario where id=l.item_id for update;
 select * into l from public.lotes_inventario where id=p_lot for update;
 if i.id is null or not i.m8_enabled or not private.has_clinic_role(i.clinic_id,array['admin']) then raise exception 'inventory_admin_required';end if;
 if p_delta is null or p_delta !~ '^-?\d{1,12}(\.\d{1,9})?$' or p_delta::numeric=0 or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'adjustment_reason_required';end if;
 if i.m8_kind='farmaco' and not exists(select 1 from public.medication_product_versions p where p.id=i.medication_version_id and private.rx_product_verified(p) and p.classification='no_controlado' and p.quantified_prescription=false) then raise exception 'controlled_or_unverified_stock_adjustment_denied';end if;
 n=p_delta::numeric;fp=jsonb_build_object('kind','stock_adjust','lot',p_lot,'delta',p_delta,'reason',p_reason);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if l.cantidad+n<0 or i.stock+n<0 then raise exception 'insufficient_stock';end if;
 update public.lotes_inventario set cantidad=cantidad+n where id=l.id;
 update public.inventario set stock=stock+n,version=version+1 where id=i.id;
 insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,created_by) values(i.clinic_id,i.id,l.id,n,'ajuste',l.costo_unitario,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_stock_adjusted',v_id);return v_id;
end $$;
revoke all on function private.inv_dispense(public.inventario,uuid,numeric) from public,anon,authenticated;
revoke all on function private.dispensing_access(uuid,uuid),private.dispensing_require(uuid),public.inv_dispensing_permissions(uuid) from public,anon,authenticated;
grant execute on function public.inv_dispensing_permissions(uuid) to authenticated;
select private.beta_install_guards();
commit;
