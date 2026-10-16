-- LOCAL CANDIDATE 13I2, after 13I1. Do not deploy independently or open beta.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('inventory.manage','Gestionar catálogo, precios y fotos',false,false),
 ('inventory.receive','Recibir lotes',false,false),
 ('inventory.order.prepare','Preparar pedidos',false,false),
 ('inventory.order.approve','Aprobar pedidos',false,false),
 ('sales.collect','Cobrar y gestionar turno propio',false,false),
 ('sales.read','Consultar caja y cortes de la clínica',false,false),
 ('sales.reverse','Revertir ventas con motivo',false,false),
 ('sales.reconcile','Conciliar referencias de pago',false,false),
 ('sales.manual','Capturar servicios fuera del catálogo',false,false),
 ('cash.move','Registrar ingresos, retiros y gastos de caja',false,false);
-- No automatic grants, professional verification, membership or historical conversion.
create function private.inventory_current(p_clinic uuid,p_code text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.member_permission_grants where id=private.permission_effective(p_clinic,auth.uid(),p_code) and valid_until>clock_timestamp());
$$;
create or replace function private.inv_access(clinic uuid) returns boolean language sql stable security definer set search_path='' as $$select private.inventory_current(clinic,'inventory.read')$$;
create function private.inventory_require(p_clinic uuid,p_code text,p_operation text default null,p_entity uuid default null,p_professional boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare g uuid;begin
 perform private.medication_lock(p_clinic);
 if not private.inv_access(p_clinic) then raise exception 'inventory_read_permission_required';end if;
 g=private.hospital_order_permission(p_clinic,p_code,null,p_professional);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'inventory_permission_used',coalesce(p_entity,p_clinic),jsonb_build_object('code',p_code,'grant_id',g,'operation',p_operation));
 return g;
end$$;
create function private.inventory_cash_read(p_clinic uuid,p_cashier uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.inv_access(p_clinic) and (private.inventory_current(p_clinic,'sales.read') or (p_cashier=auth.uid() and private.inventory_current(p_clinic,'sales.collect')));
$$;
create function private.inventory_clinical_read(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.inv_access(p_clinic) and private.inventory_current(p_clinic,'patient.read') and private.inventory_current(p_clinic,'clinical.read');
$$;
create or replace function public.inv_settings(p_clinic uuid,p_timezone text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.inventory_require(p_clinic,'inventory.manage',null,null,false);
 if not private.inventory_current(p_clinic,'inventory.manage') then raise exception 'inventory_admin_required';end if;
 if not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'timezone_required';end if;
 insert into public.inventory_clinic_settings values(p_clinic,p_timezone) on conflict(clinic_id) do update set timezone=excluded.timezone;
 insert into public.audit_log(clinic_id,actor_id,action) values(p_clinic,auth.uid(),'inventory_timezone_changed');
end $$;
create or replace function public.inv_product_save(p_clinic uuid,p_id uuid,p_version integer,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;v_id uuid;fp jsonb;price numeric;cost numeric;minimum numeric;reorder numeric;kind text;unit text;med uuid;
begin
 perform private.inventory_require(p_clinic,'inventory.manage',p_operation,p_id,false);
 if not private.inventory_current(p_clinic,'inventory.manage') then raise exception 'inventory_admin_required';end if;
 if coalesce(length(btrim(p_data->>'name')),0) not between 1 and 200 or coalesce(length(btrim(p_data->>'presentation')),0) not between 1 and 200 then raise exception 'product_fields_required';end if;
 kind=p_data->>'kind';unit=p_data->>'unit';med=nullif(p_data->>'medication_version_id','')::uuid;
 if kind not in ('producto','farmaco') or unit not in ('unidad','frasco','caja','g','kg','ml','L') then raise exception 'product_kind_unit_required';end if;
 if (kind='producto' and med is not null) or (med is not null and not exists(select 1 from public.medication_product_versions where id=med)) then raise exception 'medication_reference_mismatch';end if;
 price=private.inv_money(p_data->>'price');cost=private.inv_money(p_data->>'cost');minimum=private.inv_quantity(p_data->>'minimum',true);reorder=private.inv_quantity(p_data->>'reorder',true);
 if reorder<minimum then raise exception 'reorder_below_minimum';end if;
 fp=jsonb_build_object('kind','product','id',p_id,'version',p_version,'data',p_data);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 if p_id is null then
  insert into public.inventario(clinic_id,user_id,nombre,categoria,presentacion,precio_compra,precio_venta,stock_minimo,reorder_point,m8_kind,stock_unit,medication_version_id,m8_enabled,codigo_barras,proveedor,notas)
  values(p_clinic,auth.uid(),btrim(p_data->>'name'),kind,btrim(p_data->>'presentation'),cost,price,minimum,reorder,kind,unit,med,true,nullif(btrim(p_data->>'barcode'),''),nullif(btrim(p_data->>'supplier'),''),coalesce(p_data->>'notes','')) returning id into v_id;
 else
  select * into i from public.inventario where id=p_id and clinic_id=p_clinic for update;
  if not found or not i.m8_enabled or i.version<>p_version then raise exception 'product_revision_conflict_or_legacy';end if;
  if i.m8_kind<>kind or i.stock_unit<>unit or i.medication_version_id is distinct from med then raise exception 'inventory_product_identity_is_frozen';end if;
  update public.inventario set nombre=btrim(p_data->>'name'),presentacion=btrim(p_data->>'presentation'),precio_compra=cost,precio_venta=price,stock_minimo=minimum,reorder_point=reorder,codigo_barras=nullif(btrim(p_data->>'barcode'),''),proveedor=nullif(btrim(p_data->>'supplier'),''),notas=coalesce(p_data->>'notes',''),active=coalesce((p_data->>'active')::boolean,true),version=version+1 where id=i.id returning id into v_id;
 end if;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'inventory_product_saved',v_id);return v_id;
end $$;
create or replace function public.inv_enable_legacy(p_id uuid,p_kind text,p_unit text,p_medication uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;fp jsonb;v_id uuid;
begin
 perform private.inventory_require((select clinic_id from public.inventario where id=p_id),'inventory.manage',p_operation,p_id,false);
 select * into i from public.inventario where id=p_id for update;
 if not found or not private.inventory_current(i.clinic_id,'inventory.manage') then raise exception 'inventory_admin_required';end if;
 fp=jsonb_build_object('kind','enable_legacy','item',p_id,'type',p_kind,'unit',p_unit,'medication',p_medication);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if i.m8_enabled then raise exception 'legacy_already_enabled';end if;
 if p_kind not in ('producto','farmaco') or p_unit not in ('unidad','frasco','caja','g','kg','ml','L') or (p_kind='producto' and p_medication is not null) then raise exception 'product_kind_unit_required';end if;
 if i.stock<0 or i.stock<>(select coalesce(sum(cantidad),0) from public.lotes_inventario where item_id=i.id) then raise exception 'legacy_stock_reconciliation_required';end if;
 perform private.inv_money(i.precio_compra::text);perform private.inv_money(i.precio_venta::text);
 for l in select * from public.lotes_inventario where item_id=i.id order by id for update loop
  if l.cantidad<0 or nullif(btrim(l.lote),'') is null then raise exception 'legacy_lot_review_required';end if;
  perform private.inv_money(l.costo_unitario::text);
  if l.cantidad>0 then insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,created_by) values(i.clinic_id,i.id,l.id,l.cantidad,'apertura',l.costo_unitario,'Saldo histórico revisado por integrante autorizado',auth.uid());end if;
 end loop;
 update public.inventario set m8_enabled=true,m8_kind=p_kind,stock_unit=p_unit,medication_version_id=p_medication,reorder_point=greatest(stock_minimo,reorder_point),version=version+1 where id=i.id;
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,i.id);return i.id;
end $$;
create or replace function public.inv_lot_receive(p_item uuid,p_lot text,p_expiry date,p_quantity text,p_cost text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;v_id uuid;n numeric;cost numeric;fp jsonb;
begin
 perform private.inventory_require((select clinic_id from public.inventario where id=p_item),'inventory.receive',p_operation,p_item,false);
 select * into i from public.inventario where id=p_item for update;
 if not found or not i.m8_enabled or not private.inventory_current(i.clinic_id,'inventory.receive') then raise exception 'inventory_admin_required';end if;
 if coalesce(length(btrim(p_lot)),0) not between 1 and 200 then raise exception 'lot_required';end if;
 if i.m8_kind='farmaco' and p_expiry is null then raise exception 'drug_expiry_required';end if;
 n=private.inv_quantity(p_quantity);cost=private.inv_money(p_cost);
 fp=jsonb_build_object('kind','receive','item',p_item,'lot',p_lot,'expiry',p_expiry,'quantity',p_quantity,'cost',p_cost);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.lotes_inventario(clinic_id,user_id,item_id,lote,caducidad,cantidad,costo_unitario) values(i.clinic_id,auth.uid(),i.id,btrim(p_lot),p_expiry,n,cost) returning id into v_id;
 update public.inventario set stock=stock+n,version=version+1 where id=i.id;
 insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,created_by) values(i.clinic_id,i.id,v_id,n,'entrada',cost,'Entrada de lote capturada',auth.uid());
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_lot_received',v_id);return v_id;
end $$;
create or replace function public.inv_stock_adjust(p_lot uuid,p_delta text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;
begin
 perform private.inventory_require((select clinic_id from public.lotes_inventario where id=p_lot),'inventory.adjust',p_operation,p_lot,false);
 select * into l from public.lotes_inventario where id=p_lot;
 if l.id is null then raise exception 'inventory_admin_required';end if;
 perform private.medication_lock(l.clinic_id);
 perform private.hospital_order_permission(l.clinic_id,'inventory.adjust',null,false);
 select * into i from public.inventario where id=l.item_id for update;
 select * into l from public.lotes_inventario where id=p_lot for update;
 if i.id is null or not i.m8_enabled or not private.inventory_current(i.clinic_id,'inventory.adjust') then raise exception 'inventory_admin_required';end if;
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
create or replace function public.inv_shift_open(p_clinic uuid,p_opening text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;n numeric;
begin
 perform private.inventory_require(p_clinic,'sales.collect',p_operation,null,false);
 if not private.inv_access(p_clinic) then raise exception 'cashier_role_required';end if;
 perform pg_advisory_xact_lock(hashtextextended('inv-shift-'||p_clinic::text||auth.uid()::text,0));
 n=private.inv_money(p_opening);fp=jsonb_build_object('kind','shift_open','opening',p_opening);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_cash_shifts(clinic_id,cashier_id,opening_cash,timezone) values(p_clinic,auth.uid(),n,private.inv_timezone(p_clinic)) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end $$;
create or replace function public.inv_sale_post(p_shift uuid,p_method text,p_lines jsonb,p_expected_total text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;i public.inventario;l public.lotes_inventario;x jsonb;v_sale uuid;fp jsonb;n numeric;total numeric=0;cost numeric=0;commission numeric=0;line_total numeric;line_cost numeric;line_commission numeric;meta jsonb;name text;price numeric;prof uuid;rx uuid;v_item uuid;charge public.inventory_application_charges;delivery public.inventory_delivery_tickets;act public.clinic_service_acts;person uuid;
begin
 perform private.medication_lock((select clinic_id from public.inventory_cash_shifts where id=p_shift));
 -- Lock every identity in order before the collect helper locks the actor.
 -- A multi-clinic user must not hold actor A then wait on issuer B out of order.
 for person in select distinct actor_id from (
 select auth.uid() as actor_id union
 select pr.responsible_id from jsonb_array_elements(p_lines) e(value)
 join public.prescription_items pi on pi.id=nullif(e.value->>'prescription_item_id','')::uuid
 join public.prescriptions pr on pr.id=pi.prescription_id
 where pr.clinic_id=(select clinic_id from public.inventory_cash_shifts where id=p_shift) and e.value->>'kind'='producto'
 ) people where actor_id is not null order by actor_id loop
 perform pg_advisory_xact_lock(hashtextextended(person::text,9061));end loop;
 perform private.inventory_require((select clinic_id from public.inventory_cash_shifts where id=p_shift),'sales.collect',p_operation,p_shift,false);
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
 end loop;
 for x in select * from jsonb_array_elements(p_lines) where value->>'kind'='servicio' and nullif(value->>'charge_id','') is null and nullif(value->>'delivery_id','') is null and nullif(value->>'service_act_id','') is null loop
 perform private.inventory_require(sh.clinic_id,'sales.manual',p_operation);end loop;
 return v_sale;end if;
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
   perform private.inventory_require(sh.clinic_id,'sales.manual',p_operation);
   if not private.inventory_current(sh.clinic_id,'sales.manual') then raise exception 'service_capture_admin_until_m9';end if;
   name=btrim(x->>'name');if coalesce(length(name),0) not between 1 and 200 then raise exception 'service_name_required';end if;
   price=private.inv_money(x->>'price');line_cost=private.inv_money(x->>'cost');line_commission=private.inv_money(x->>'commission');
   prof=nullif(x->>'professional_id','')::uuid;
   if prof is not null and not exists(select 1 from public.clinic_members where clinic_id=sh.clinic_id and user_id=prof) then raise exception 'service_professional_wrong_clinic';end if;
   if line_commission>0 and prof is null then raise exception 'commission_professional_required';end if;
   meta=jsonb_build_object('service_catalog','captura manual autorizada','commission_basis','Importe total capturado por persona autorizada');
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
 perform private.inventory_require((select clinic_id from public.inventory_cash_shifts where id=p_shift),'sales.reverse',p_operation,p_sale,false);
 perform private.hospital_order_permission((select clinic_id from public.inventory_cash_shifts where id=p_shift),'sales.collect',null,false);
 select * into sh from public.inventory_cash_shifts where id=p_shift;
 if not found then raise exception 'reversal_admin_own_shift_required';end if;
 perform private.medication_lock(sh.clinic_id);
 if exists(select 1 from public.inventory_sale_lines sl join public.inventario i on i.id=sl.item_id where sl.sale_id=p_sale and sl.clinic_id=sh.clinic_id and i.m8_kind='farmaco') then perform private.dispensing_require(sh.clinic_id);end if;
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 select * into s from public.inventory_sales where id=p_sale and clinic_id=sh.clinic_id for update;
 if s.id is null or sh.cashier_id<>auth.uid() or not private.inventory_current(sh.clinic_id,'sales.reverse') then raise exception 'reversal_admin_own_shift_required';end if;
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
create or replace function public.inv_cash_move(p_shift uuid,p_kind text,p_amount text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;v_id uuid;fp jsonb;n numeric;
begin
 perform private.inventory_require((select clinic_id from public.inventory_cash_shifts where id=p_shift),'cash.move',p_operation,p_shift,false);
 perform private.hospital_order_permission((select clinic_id from public.inventory_cash_shifts where id=p_shift),'sales.collect',null,false);
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 if sh.id is null or sh.cashier_id<>auth.uid() or not private.inv_access(sh.clinic_id) then raise exception 'own_shift_required';end if;
 fp=jsonb_build_object('kind','cash_move','shift',p_shift,'type',p_kind,'amount',p_amount,'reason',p_reason);v_id=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if sh.closed_at is not null then raise exception 'closed_shift';end if;
 if p_kind not in ('ingreso','retiro','gasto') or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'cash_reason_required';end if;
 n=private.inv_money(p_amount);if n<=0 then raise exception 'positive_amount_required';end if;
 insert into public.inventory_cash_movements(clinic_id,shift_id,kind,amount,reason,created_by) values(sh.clinic_id,sh.id,p_kind,n,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),sh.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(sh.clinic_id,auth.uid(),'inventory_cash_movement',v_id);return v_id;
end $$;
create or replace function public.inv_shift_close(p_shift uuid,p_counted text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;v_snapshot jsonb;n numeric;difference numeric;fp jsonb;v_id uuid;
begin
 perform private.inventory_require((select clinic_id from public.inventory_cash_shifts where id=p_shift),'sales.collect',p_operation,p_shift,false);
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 if not found or sh.cashier_id<>auth.uid() or not private.inv_access(sh.clinic_id) then raise exception 'own_shift_required';end if;
 fp=jsonb_build_object('kind','close_shift','shift',p_shift,'counted',p_counted,'reason',p_reason);v_id=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if sh.closed_at is not null then raise exception 'closed_shift';end if;
 n=private.inv_money(p_counted);v_snapshot=public.inv_shift_snapshot(sh.id);difference=n-(v_snapshot->>'expected_cash')::numeric;
 if difference<>0 and coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'cash_discrepancy_reason_required';end if;
 v_snapshot=v_snapshot||jsonb_build_object('closed_at',clock_timestamp(),'counted_cash',n::text,'difference',difference::text,'reason',coalesce(p_reason,''));
 update public.inventory_cash_shifts set closed_at=(v_snapshot->>'closed_at')::timestamptz,counted_cash=n,snapshot=v_snapshot where id=sh.id;
 insert into private.vet_operation_receipts values(auth.uid(),sh.clinic_id,p_operation,fp,sh.id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(sh.clinic_id,auth.uid(),'inventory_shift_closed',sh.id);return sh.id;
end $$;
create or replace function public.inv_order_draft(p_clinic uuid,p_supplier text,p_message text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;
begin
 perform private.inventory_require(p_clinic,'inventory.order.prepare',p_operation,null,false);
 if not private.inventory_current(p_clinic,'inventory.order.prepare') then raise exception 'inventory_admin_required';end if;
 if coalesce(length(btrim(p_supplier)),0) not between 1 and 200 or coalesce(length(btrim(p_message)),0) not between 1 and 8000 then raise exception 'order_fields_required';end if;
 fp=jsonb_build_object('kind','order','supplier',p_supplier,'message',p_message);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_order_drafts(clinic_id,supplier,message,created_by) values(p_clinic,btrim(p_supplier),p_message,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end $$;
create or replace function public.inv_order_approve(p_id uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.inventory_order_drafts;v_id uuid;fp jsonb;
begin
 perform private.inventory_require((select clinic_id from public.inventory_order_drafts where id=p_id),'inventory.order.approve',p_operation,p_id,false);
 select * into d from public.inventory_order_drafts where id=p_id for update;
 if not found or not private.inventory_current(d.clinic_id,'inventory.order.approve') then raise exception 'inventory_admin_required';end if;
 fp=jsonb_build_object('kind','approve_order','draft',p_id);v_id=private.vet_receipt(d.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_order_approvals(draft_id,clinic_id,approved_by) values(d.id,d.clinic_id,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'inventory_order_approved',d.id);return v_id;
end $$;
create or replace function public.inv_vial_link(p_vial uuid,p_lot uuid,p_packages text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.medication_vials;i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;
begin
 perform private.inventory_require((select clinic_id from public.medication_vials where id=p_vial),'vial.manage',p_operation,p_vial,true);
 select * into v from public.medication_vials where id=p_vial;
 if not found or v.responsible_id<>auth.uid() or not private.clinical_professional_at(v.clinic_id,auth.uid(),clock_timestamp()) then raise exception 'vial_responsible_required';end if;
 select * into l from public.lotes_inventario where id=p_lot and clinic_id=v.clinic_id;
 select * into i from public.inventario where id=l.item_id for update;
 select * into l from public.lotes_inventario where id=p_lot for update;
 fp=jsonb_build_object('kind','vial_link','vial',p_vial,'lot',p_lot,'packages',p_packages);v_id=private.vet_receipt(v.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 n=private.inv_quantity(p_packages);
 if i.id is null or not i.m8_enabled or not i.active or i.m8_kind<>'farmaco' or i.medication_version_id<>v.product_version_id or l.lote<>v.lot or i.stock_unit not in ('unidad','frasco','caja') or n<>trunc(n) then raise exception 'vial_inventory_identity_mismatch';end if;
 if v.inventory_id is not null and v.inventory_id<>i.id or v.inventory_lot_id is not null and v.inventory_lot_id<>l.id then raise exception 'vial_inventory_identity_mismatch';end if;
 if l.caducidad is null or l.caducidad<=(clock_timestamp() at time zone private.inv_timezone(v.clinic_id))::date then raise exception 'expired_lot_blocked';end if;
 if l.cantidad<n or i.stock<n then raise exception 'insufficient_stock';end if;
 if exists(select 1 from public.inventory_vial_links where vial_id=v.id) then raise exception 'vial_already_linked';end if;
 update public.lotes_inventario set cantidad=cantidad-n where id=l.id;
 update public.inventario set stock=stock-n,version=version+1 where id=i.id;
 insert into public.inventory_vial_links(clinic_id,vial_id,lot_id,packages,created_by) values(v.clinic_id,v.id,l.id,n,auth.uid()) returning id into v_id;
 insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,source_id,created_by) values(v.clinic_id,i.id,l.id,-n,'frasco',l.costo_unitario,'Envase abierto vinculado a M6; las tomas descuentan solo volumen M6',v_id,auth.uid());
 insert into private.vet_operation_receipts values(auth.uid(),v.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(v.clinic_id,auth.uid(),'inventory_vial_linked',v_id);return v_id;
end $$;
create or replace function public.inv_application_tariff(p_clinic uuid,p_product uuid,p_price text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;n numeric;
begin
 perform private.inventory_require(p_clinic,'inventory.manage',p_operation,null,false);
 if not private.inventory_current(p_clinic,'inventory.manage') then raise exception 'inventory_admin_required';end if;
 if not exists(select 1 from public.medication_product_versions where id=p_product) then raise exception 'product_version_required';end if;
 n=private.inv_money(p_price);fp=jsonb_build_object('kind','application_tariff','product',p_product,'price',p_price);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_application_tariffs(clinic_id,product_version_id,price,created_by) values(p_clinic,p_product,n,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end $$;
create or replace function public.inv_application_prepare(p_record uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.medication_records;c public.clinical_cases;p public.medication_product_versions;rx public.prescriptions;t public.inventory_application_tariffs;v public.medication_vials;l public.lotes_inventario;link public.inventory_vial_links;root uuid;v_id uuid;fp jsonb;cost numeric=0;pending boolean=true;
begin
 perform private.inventory_require((select clinic_id from public.medication_records where id=p_record),'sales.collect',p_operation,p_record,false);
 select * into r from public.medication_records where id=p_record for update;
 select * into c from public.clinical_cases where id=r.case_id;
 if r.id is null or not private.clinical_readable(c) or not private.inventory_clinical_read(r.clinic_id) then raise exception 'clinical_case_access_required';end if;
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
create or replace function public.inv_photo_attach(p_item uuid,p_version integer,p_path text) returns void language plpgsql security definer set search_path='' as $$
declare i public.inventario;
begin
 perform private.inventory_require((select clinic_id from public.inventario where id=p_item),'inventory.manage',null,p_item,false);
 select * into i from public.inventario where id=p_item for update;
 if not found or not private.inventory_current(i.clinic_id,'inventory.manage') or not private.inv_photo_allowed(p_path,true) or split_part(p_path,'/',2)<>i.id::text then raise exception 'photo_scope_denied';end if;
 if i.version<>p_version then raise exception 'product_revision_conflict_or_legacy';end if;
 if not exists(select 1 from storage.objects where bucket_id='inventory-photos' and name=p_path) then raise exception 'photo_upload_required';end if;
 update public.inventario set photo_path=p_path,version=version+1 where id=i.id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_photo_attached',i.id);
end $$;
create or replace function private.inv_photo_allowed(p_path text,p_write boolean) returns boolean language plpgsql volatile security definer set search_path='' as $$
declare clinic uuid;item uuid;
begin
 if p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{48}\.(jpg|png)$' then return false;end if;
 begin clinic=split_part(p_path,'/',1)::uuid;item=split_part(p_path,'/',2)::uuid;exception when invalid_text_representation then return false;end;
 if p_write then
 if not private.inv_access(clinic) or not private.inventory_current(clinic,'inventory.manage') then return false;end if;
 perform private.inventory_require(clinic,'inventory.manage',null,item);end if;
 return exists(select 1 from public.inventario where id=item and clinic_id=clinic and m8_enabled) and case when p_write then private.inventory_current(clinic,'inventory.manage') else private.inv_access(clinic) end;
end $$;
create function private.inventory_safe_cut(p_cut jsonb,p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 -- Cash/export always returns accounting data; clinical originals stay in their module.
 select coalesce(jsonb_agg(s.value||jsonb_build_object('lines',coalesce((select jsonb_agg((l.value-'metadata'-'prescription_item_id')||jsonb_build_object('metadata','{}'::jsonb,'name',case when nullif(l.value->>'application_charge_id','') is not null then 'Cargo por aplicación' when nullif(l.value->>'delivery_ticket_id','') is not null then 'Entrega de producto' when nullif(l.value->>'service_act_id','') is not null then 'Servicio registrado' else l.value->>'name' end)) from jsonb_array_elements(coalesce(s.value->'lines','[]')) l(value)),'[]'))),'[]') into result from jsonb_array_elements(coalesce(p_cut->'sales','[]')) s(value);
 return jsonb_set(p_cut,'{sales}',result);
end$$;
create or replace function public.inv_shift_snapshot(p_shift uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;totals jsonb;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift;
 if not found or not private.inventory_cash_read(sh.clinic_id,sh.cashier_id) then raise exception 'shift_access_required';end if;
 if sh.closed_at is not null then return private.inventory_safe_cut(sh.snapshot,sh.clinic_id);end if;
 totals=private.inv_totals(sh.clinic_id,sh.id,null,null);
 return private.inventory_safe_cut(jsonb_build_object('shift_id',sh.id,'clinic_id',sh.clinic_id,'cashier_id',sh.cashier_id,'opened_at',sh.opened_at,'timezone',sh.timezone,'cutoff',clock_timestamp(),'opening_cash',sh.opening_cash::text,'totals',totals,
 'expected_cash',(sh.opening_cash+(totals->>'cash')::numeric+(totals->>'income')::numeric-(totals->>'withdrawal')::numeric-(totals->>'expense')::numeric)::text,
 'sales',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('total',s.total::text,'cost',s.cost::text,'commission',s.commission::text,'lines',(select jsonb_agg(to_jsonb(l)||jsonb_build_object('quantity',l.quantity::text,'price',l.price::text,'total',l.total::text,'cost',l.cost::text,'commission',l.commission::text)) from public.inventory_sale_lines l where sale_id=s.id))) from public.inventory_sales s where shift_id=sh.id),'[]'),
 'reversals',coalesce((select jsonb_agg(to_jsonb(r)) from public.inventory_sale_reversals r where shift_id=sh.id),'[]'),
 'cash_movements',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('amount',m.amount::text)) from public.inventory_cash_movements m where shift_id=sh.id),'[]')),sh.clinic_id);
end $$;
create or replace function public.inv_dashboard(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text;today date;start_at timestamptz;end_at timestamptz;
begin
 if not private.inv_access(p_clinic) then raise exception 'inventory_access_required';end if;
 tz=private.inv_timezone(p_clinic);today=(clock_timestamp() at time zone tz)::date;start_at=today::timestamp at time zone tz;end_at=(today+1)::timestamp at time zone tz;
 return jsonb_build_object('professional',private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()),'timezone',tz,'today',today,'server_time',clock_timestamp(),
 'products',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('stock',i.stock::text,'stock_minimo',i.stock_minimo::text,'reorder_point',i.reorder_point::text,'precio_compra',i.precio_compra::text,'precio_venta',i.precio_venta::text,'available_stock',available::text,'low_stock',available<=i.stock_minimo,'reorder',available<=i.reorder_point,'lots',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('cantidad',l.cantidad::text,'costo_unitario',l.costo_unitario::text,'days',l.caducidad-today,'expired',l.caducidad<=today) order by l.caducidad nulls last,l.created_at) from public.lotes_inventario l where item_id=i.id),'[]')) order by i.nombre) from public.inventario i cross join lateral(select coalesce(sum(l.cantidad),0) available from public.lotes_inventario l where l.item_id=i.id and (l.caducidad>today or (l.caducidad is null and i.m8_kind='producto'))) a where i.clinic_id=p_clinic),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(sh)-'snapshot'||jsonb_build_object('opening_cash',sh.opening_cash::text,'counted_cash',sh.counted_cash::text) order by sh.opened_at desc) from public.inventory_cash_shifts sh where clinic_id=p_clinic and private.inventory_cash_read(p_clinic,cashier_id)),'[]'),
 'day_totals',case when private.inventory_current(p_clinic,'sales.read') then private.inv_totals(p_clinic,null,start_at,end_at) else null end,
 'catalog',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status)) from public.medication_product_versions p where p.version=(select max(v.version) from public.medication_product_versions v where v.product_key=p.product_key)),'[]'),
 'staff',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'role',m.role,'label',coalesce(u.email,m.user_id::text))) from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=p_clinic),'[]'),
 'prescription_items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'product_version_id',x.product_version_id,'prescription_id',r.id,'folio',r.official_folio,'patient_id',r.patient_id)) from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.clinic_id=p_clinic and r.state='issued' and private.dispensing_access(p_clinic,auth.uid()) and private.rx_readable(r)),'[]'),
 'top_products',case when private.inventory_current(p_clinic,'sales.read') then coalesce((
 select jsonb_agg(jsonb_build_object('id',x.item_id,'name',i.nombre,'unit',i.stock_unit,'quantity',x.quantity::text,'amount',x.amount::text) order by x.amount desc) from (
 select f.item_id,sum(f.quantity) quantity,sum(f.amount) amount from (
 select l.item_id,l.quantity,l.total amount from public.inventory_sale_lines l join public.inventory_sales s on s.id=l.sale_id where l.clinic_id=p_clinic and l.kind='producto' and s.created_at>=start_at-interval '29 days' and s.created_at<end_at
 union all select l.item_id,-l.quantity,-l.total from public.inventory_sale_lines l join public.inventory_sale_reversals r on r.sale_id=l.sale_id where l.clinic_id=p_clinic and l.kind='producto' and r.created_at>=start_at-interval '29 days' and r.created_at<end_at
 ) f group by f.item_id having sum(f.amount)>0 order by sum(f.amount) desc limit 10) x join public.inventario i on i.id=x.item_id),'[]') else '[]'::jsonb end,
 'orders',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('approval',(select to_jsonb(a) from public.inventory_order_approvals a where draft_id=d.id)) order by d.created_at desc) from public.inventory_order_drafts d where clinic_id=p_clinic),'[]'));
end $$;
create or replace function public.inv_workflow_dashboard(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare clinical boolean;billing boolean;begin
 if not private.inv_access(p_clinic) then raise exception 'inventory_access_required';end if;
 clinical=private.inventory_clinical_read(p_clinic);
 billing=private.inventory_current(p_clinic,'sales.collect') or private.inventory_current(p_clinic,'sales.read');
 return jsonb_build_object(
 'deliveries',case when billing or clinical then coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'name','Entrega de producto','price',d.price::text,'cost',d.cost::text,'reference','{}'::jsonb,'paid',exists(select 1 from public.inventory_sale_lines sl where sl.delivery_ticket_id=d.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id)))) from public.inventory_delivery_tickets d where d.clinic_id=p_clinic),'[]') else '[]'::jsonb end,
 'charges',case when billing or clinical then coalesce((select jsonb_agg(jsonb_build_object('id',ch.id,'name','Cargo por aplicación','price',ch.price::text,'cost',ch.cost::text,'cost_pending',ch.cost_pending,'reference','{}'::jsonb,'paid',exists(select 1 from public.inventory_sale_lines sl where sl.application_charge_id=ch.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id)))) from public.inventory_application_charges ch where ch.clinic_id=p_clinic),'[]') else '[]'::jsonb end,
 'applications',case when clinical and private.inventory_current(p_clinic,'sales.collect') then coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',p.name,'quantity',r.quantity::text,'unit',r.unit,'observed_at',r.observed_at,'prescription_id',r.prescription_id)) from public.medication_records r join public.medication_product_versions p on p.id=r.product_version_id where r.clinic_id=p_clinic and r.prescription_id is not null and not exists(select 1 from public.medication_records n where n.replaces_id=r.id)),'[]') else '[]'::jsonb end,
 'grants',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('revoked',exists(select 1 from public.inventory_delivery_revocations rv where rv.grant_id=g.id))) from public.inventory_delivery_grants g where g.clinic_id=p_clinic and (g.responsible_id=auth.uid() or g.recipient_id=auth.uid())),'[]'));
end$$;
create function public.inv_billable_services(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.inv_access(p_clinic) or not private.inventory_current(p_clinic,'sales.collect') then raise exception 'cash_collection_permission_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',case when private.inventory_clinical_read(p_clinic) then a.name else 'Servicio registrado' end,'price',a.price::text,'commission',a.commission::text,'professional_id',a.professional_id)) from public.clinic_service_acts a where a.clinic_id=p_clinic and not exists(select 1 from public.inventory_sale_lines l where l.service_act_id=a.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=l.sale_id))),'[]');
end$$;
create function public.inv_management_permissions(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.inv_access(p_clinic) then raise exception 'inventory_read_permission_required';end if;
 return jsonb_build_object('schema_version',1,'mode','explicit_inventory','actions',(select jsonb_object_agg(code,private.inventory_current(p_clinic,code)) from private.permission_catalog where code in ('inventory.read','inventory.manage','inventory.receive','inventory.adjust','inventory.order.prepare','inventory.order.approve','sales.collect','sales.read','sales.reverse','sales.reconcile','sales.manual','cash.move')),'can_link_vial',private.inventory_current(p_clinic,'vial.manage') and private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()),'can_prepare_charge',private.inventory_current(p_clinic,'sales.collect') and private.inventory_clinical_read(p_clinic));
end$$;
create function private.inventory_dispensing_read(p_clinic uuid) returns boolean language sql stable security definer set search_path='' as $$select private.dispensing_access(p_clinic,auth.uid())$$;
do $$declare p record;begin
 for p in select tablename,policyname from pg_policies where schemaname='public' and tablename=any(array['inventario','lotes_inventario','inventory_clinic_settings','inventory_stock_movements','inventory_cash_shifts','inventory_sales','inventory_sale_lines','inventory_sale_reversals','inventory_cash_movements','inventory_order_drafts','inventory_order_approvals','inventory_vial_links','inventory_dispensing_limits','inventory_application_tariffs','inventory_application_charges','inventory_delivery_tickets','inventory_delivery_grants','inventory_delivery_revocations']) loop execute format('drop policy %I on public.%I',p.policyname,p.tablename);end loop;end$$;
create policy inv_explicit_read on public.inventario for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.lotes_inventario for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.inventory_clinic_settings for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.inventory_stock_movements for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.inventory_cash_shifts for select to authenticated using(private.inventory_cash_read(clinic_id,cashier_id));
create policy inv_explicit_read on public.inventory_sales for select to authenticated using(private.inventory_cash_read(clinic_id,cashier_id));
create policy inv_explicit_read on public.inventory_sale_lines for select to authenticated using(false);
create policy inv_explicit_read on public.inventory_sale_reversals for select to authenticated using(exists(select 1 from public.inventory_cash_shifts sh where sh.id=shift_id and private.inventory_cash_read(sh.clinic_id,sh.cashier_id)));
create policy inv_explicit_read on public.inventory_cash_movements for select to authenticated using(exists(select 1 from public.inventory_cash_shifts sh where sh.id=shift_id and private.inventory_cash_read(sh.clinic_id,sh.cashier_id)));
create policy inv_explicit_read on public.inventory_order_drafts for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.inventory_order_approvals for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.inventory_vial_links for select to authenticated using(private.inv_access(clinic_id) and private.inventory_current(clinic_id,'vial.read'));
create policy inv_explicit_read on public.inventory_dispensing_limits for select to authenticated using(private.inventory_dispensing_read(clinic_id));
create policy inv_explicit_read on public.inventory_application_tariffs for select to authenticated using(private.inv_access(clinic_id));
create policy inv_explicit_read on public.inventory_application_charges for select to authenticated using(false);
create policy inv_explicit_read on public.inventory_delivery_tickets for select to authenticated using(false);
create policy inv_explicit_read on public.inventory_delivery_grants for select to authenticated using(private.inv_access(clinic_id) and (responsible_id=auth.uid() or recipient_id=auth.uid()));
create policy inv_explicit_read on public.inventory_delivery_revocations for select to authenticated using(exists(select 1 from public.inventory_delivery_grants g where g.id=grant_id));
-- A frozen cash cut may contain clinical metadata: only the sanitized RPC returns it.
revoke select on public.inventory_cash_shifts from authenticated;
do $$declare cols text;begin
 select string_agg(quote_ident(column_name),',') into cols from information_schema.columns where table_schema='public' and table_name='inventory_cash_shifts' and column_name<>'snapshot';
 execute 'grant select ('||cols||') on public.inventory_cash_shifts to authenticated';end$$;
revoke all on function private.dispensing_access(uuid,uuid),private.inventory_dispensing_read(uuid) from public,anon,authenticated;
revoke all on function private.inventory_current(uuid,text),private.inventory_require(uuid,text,text,uuid,boolean),private.inventory_cash_read(uuid,uuid),private.inventory_clinical_read(uuid),private.inventory_safe_cut(jsonb,uuid),public.inv_billable_services(uuid),public.inv_management_permissions(uuid) from public,anon,authenticated;
grant execute on function private.inventory_current(uuid,text),private.inventory_cash_read(uuid,uuid),private.inventory_clinical_read(uuid),private.inventory_dispensing_read(uuid),public.inv_billable_services(uuid),public.inv_management_permissions(uuid) to authenticated;
create or replace function public.pay_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.inventory_cash_read(p_clinic,auth.uid()) then raise exception 'access_denied';end if;
 return jsonb_build_object(
 'sales',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'method',s.method,'total',s.total::text,'created_at',s.created_at,'cashier_id',s.cashier_id,'reversed',exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=s.id)) order by s.created_at desc),'[]') from public.inventory_sales s where clinic_id=p_clinic and ((cashier_id=auth.uid() and private.inventory_current(p_clinic,'sales.collect')) or private.inventory_current(p_clinic,'sales.read'))),
 'transactions',(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('amount',t.amount::text,'state',coalesce(r.decision,'pendiente_revision'),'fee',r.fee::text,'net',case when r.decision='verificada' then (t.amount-r.fee)::text end,'review_reason',r.reason) order by t.reported_at desc),'[]') from public.payment_transactions t left join lateral (select * from public.payment_reconciliations r where r.transaction_id=t.id order by reviewed_at desc,id desc limit 1) r on true where t.clinic_id=p_clinic and ((t.reported_by=auth.uid() and private.inventory_current(p_clinic,'sales.collect')) or private.inventory_current(p_clinic,'sales.read'))));
end$$;
create or replace function public.pay_report(p_clinic uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare fp jsonb;v_id uuid;s public.inventory_sales;amount numeric;ref text;
begin
 perform private.inventory_require(p_clinic,'sales.collect',p_operation);
 if not private.inv_access(p_clinic) then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'invalid_data';end if;
 -- Reject unexpected fields rather than storing raw provider/card payloads.
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in ('sale_id','direction','method','amount','provider','external_reference','occurred_at','card_last_four','notes')) then raise exception 'unsupported_payment_fields';end if;
 fp=jsonb_build_object('kind','payment_reference','data',p_data);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 amount=private.inv_money(p_data->>'amount');ref=nullif(btrim(p_data->>'external_reference'),'');
 if nullif(p_data->>'sale_id','') is not null then
 select * into s from public.inventory_sales where id=(p_data->>'sale_id')::uuid and clinic_id=p_clinic for share;
 if not found or not (s.cashier_id=auth.uid() or private.inventory_current(p_clinic,'sales.read')) then raise exception 'own_sale_required';end if;
 if exists(select 1 from public.inventory_sale_reversals where sale_id=s.id) then raise exception 'reversed_sale';end if;
 if amount>s.total or p_data->>'method'<>s.method then raise exception 'payment_sale_mismatch';end if;
 end if;
 insert into public.payment_transactions(clinic_id,sale_id,direction,method,amount,provider,external_reference,occurred_at,card_last_four,notes,reported_by)
 values(p_clinic,s.id,p_data->>'direction',p_data->>'method',amount,lower(btrim(p_data->>'provider')),ref,(p_data->>'occurred_at')::timestamptz,nullif(p_data->>'card_last_four',''),coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'payment_reported',v_id::text);
 return v_id;
end$$;
create or replace function public.pay_reconcile(p_id uuid,p_decision text,p_fee text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare t public.payment_transactions;v_id uuid;fp jsonb;fee numeric;allocated numeric;total numeric;
begin
 perform private.inventory_require((select clinic_id from public.payment_transactions where id=p_id),'sales.reconcile',p_operation,p_id);
 perform private.hospital_order_permission((select clinic_id from public.payment_transactions where id=p_id),'sales.read',null,false);
 select * into t from public.payment_transactions where id=p_id for update;
 if not found or not private.inventory_current(t.clinic_id,'sales.reconcile') then raise exception 'admin_required';end if;
 fp=jsonb_build_object('kind','payment_reconcile','id',p_id,'decision',p_decision,'fee',p_fee,'reason',p_reason);v_id=private.vet_receipt(t.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 fee=private.inv_money(p_fee);if fee>t.amount then raise exception 'fee_exceeds_payment';end if;
 if t.sale_id is not null and p_decision='verificada' then
 select s.total into total from public.inventory_sales s where id=t.sale_id for update;
 if exists(select 1 from public.inventory_sale_reversals where sale_id=t.sale_id) then raise exception 'reversed_sale';end if;
 select coalesce(sum(x.amount),0) into allocated from public.payment_transactions x join lateral (select decision from public.payment_reconciliations r where r.transaction_id=x.id order by reviewed_at desc,id desc limit 1) r on r.decision='verificada' where x.sale_id=t.sale_id and x.id<>t.id;
 if allocated+t.amount>total then raise exception 'payment_allocation_exceeds_sale';end if;
 end if;
 insert into public.payment_reconciliations(clinic_id,transaction_id,decision,fee,reason,reviewed_by) values(t.clinic_id,t.id,p_decision,fee,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),t.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(t.clinic_id,auth.uid(),'payment_reconciled',v_id::text);
 return v_id;
end$$;
select private.beta_install_guards();
commit;
