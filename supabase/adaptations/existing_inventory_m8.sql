-- M8: additive adaptation of the EXISTING inventory/lot tables.
-- Apply ONCE after M2, M4, M5 and M-FORMATOS/M6; not applied remotely.
begin;
alter table public.inventario add column m8_enabled boolean not null default false,
 add column m8_kind text not null default 'sin_clasificar' check(m8_kind in ('sin_clasificar','producto','farmaco')),
 add column stock_unit text not null default 'unidad',add column reorder_point numeric(24,9) not null default 0 check(reorder_point>=0),
 add column medication_version_id uuid references public.medication_product_versions(id),add column active boolean not null default true,
 add column version integer not null default 1,add column photo_path text;
create unique index inv_clinic_identity on public.inventario(clinic_id,id);
create unique index inv_lot_clinic_identity on public.lotes_inventario(clinic_id,id);
-- Fail safely on foreign-clinic legacy lots; never guess their owner.
do $$begin
 if exists(select 1 from public.lotes_inventario l join public.inventario i on i.id=l.item_id where l.clinic_id is distinct from i.clinic_id) then raise exception 'legacy_inventory_scope_review_required';end if;
end $$;
alter table public.lotes_inventario add constraint inv_lot_same_clinic foreign key(clinic_id,item_id) references public.inventario(clinic_id,id);
create table public.inventory_clinic_settings(clinic_id uuid primary key references public.clinics(id),timezone text not null default 'America/Mexico_City');
create table public.inventory_stock_movements(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,item_id uuid not null,lot_id uuid not null,
 delta numeric(24,9) not null check(delta<>0),kind text not null check(kind in ('apertura','entrada','ajuste','venta','reverso','frasco')),
 unit_cost numeric(18,2) not null check(unit_cost>=0),reason text not null,source_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,item_id) references public.inventario(clinic_id,id),foreign key(clinic_id,lot_id) references public.lotes_inventario(clinic_id,id));
create table public.inventory_cash_shifts(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),cashier_id uuid not null references auth.users(id),
 opening_cash numeric(18,2) not null check(opening_cash>=0),opened_at timestamptz not null default clock_timestamp(),timezone text not null,
 closed_at timestamptz,counted_cash numeric(18,2),snapshot jsonb,unique(clinic_id,id));
create unique index inv_open_shift on public.inventory_cash_shifts(clinic_id,cashier_id) where closed_at is null;
create table public.inventory_sales(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,shift_id uuid not null,cashier_id uuid not null references auth.users(id),
 method text not null check(method in ('efectivo','tarjeta','transferencia')),total numeric(18,2) not null check(total>0),
 cost numeric(18,2) not null check(cost>=0),commission numeric(18,2) not null check(commission>=0),
 created_at timestamptz not null default clock_timestamp(),unique(clinic_id,id),
 foreign key(clinic_id,shift_id) references public.inventory_cash_shifts(clinic_id,id));
create table public.inventory_sale_lines(
 id uuid primary key default gen_random_uuid(),sale_id uuid not null,clinic_id uuid not null,
 kind text not null check(kind in ('producto','servicio')),item_id uuid,lot_id uuid,prescription_item_id uuid references public.prescription_items(id),
 name text not null,lot text,quantity numeric(24,9) not null check(quantity>0),stock_unit text,
 price numeric(18,2) not null check(price>=0),cost numeric(18,2) not null check(cost>=0),total numeric(18,2) not null check(total>=0),
 commission numeric(18,2) not null default 0 check(commission>=0),professional_id uuid references auth.users(id),metadata jsonb not null,
 foreign key(clinic_id,sale_id) references public.inventory_sales(clinic_id,id) deferrable initially deferred,foreign key(clinic_id,item_id) references public.inventario(clinic_id,id),foreign key(clinic_id,lot_id) references public.lotes_inventario(clinic_id,id));
create table public.inventory_sale_reversals(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,sale_id uuid not null unique,shift_id uuid not null,
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,sale_id) references public.inventory_sales(clinic_id,id) deferrable initially deferred,foreign key(clinic_id,shift_id) references public.inventory_cash_shifts(clinic_id,id));
create table public.inventory_cash_movements(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,shift_id uuid not null,
 kind text not null check(kind in ('ingreso','retiro','gasto')),amount numeric(18,2) not null check(amount>0),reason text not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),foreign key(clinic_id,shift_id) references public.inventory_cash_shifts(clinic_id,id));
create table public.inventory_order_drafts(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),supplier text not null,
 message text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create table public.inventory_order_approvals(
 id uuid primary key default gen_random_uuid(),draft_id uuid not null unique references public.inventory_order_drafts(id),
 clinic_id uuid not null references public.clinics(id),approved_by uuid not null references auth.users(id),approved_at timestamptz not null default clock_timestamp());
create table public.inventory_vial_links(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,vial_id uuid not null unique references public.medication_vials(id),lot_id uuid not null,
 packages numeric(24,9) not null check(packages>0),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,lot_id) references public.lotes_inventario(clinic_id,id),foreign key(clinic_id,vial_id) references public.medication_vials(clinic_id,id));

create table public.inventory_dispensing_limits(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,item_id uuid not null,prescription_item_id uuid not null references public.prescription_items(id),
 quantity numeric(24,9) not null check(quantity>=0),valid_until timestamptz not null,reason text not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,item_id) references public.inventario(clinic_id,id));
alter table public.inventory_vial_links add constraint inv_vial_same_clinic foreign key(clinic_id,vial_id) references public.medication_vials(clinic_id,id);
create function private.inv_access(clinic uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_clinic_role($1,array['admin','mvz','auxiliar','recepcion']); $$;
create function private.inv_money(value text) returns numeric language plpgsql immutable set search_path='' as $$
begin if value is null or value !~ '^\d{1,12}(\.\d{1,2})?$' then raise exception 'exact_mxn_money_required';end if;return value::numeric;end $$;
create function private.inv_quantity(value text,allow_zero boolean default false) returns numeric language plpgsql immutable set search_path='' as $$
begin if value is null or value !~ '^\d{1,12}(\.\d{1,9})?$' or (not allow_zero and value::numeric=0) then raise exception 'exact_stock_quantity_required';end if;return value::numeric;end $$;
create function private.inv_timezone(clinic uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce((select timezone from public.inventory_clinic_settings where clinic_id=$1),'America/Mexico_City'); $$;
create function private.inv_history_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_table_name='inventory_cash_shifts' then
 if tg_op='UPDATE' and old.closed_at is null then
  if new.clinic_id<>old.clinic_id or new.cashier_id<>old.cashier_id or new.opening_cash<>old.opening_cash or new.opened_at<>old.opened_at or new.timezone<>old.timezone then raise exception 'shift_identity_is_immutable';end if;return new;
 end if;
 end if;
 raise exception 'inventory_history_is_immutable';
end $$;
create function private.inv_identity_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.id<>old.id or new.clinic_id is distinct from old.clinic_id or new.user_id<>old.user_id then raise exception 'inventory_identity_is_immutable';end if;
 if tg_table_name='inventario' then
  if old.m8_enabled and (new.m8_kind<>old.m8_kind or new.stock_unit<>old.stock_unit or new.medication_version_id is distinct from old.medication_version_id or not new.m8_enabled) then raise exception 'inventory_product_identity_is_frozen';end if;
 else
  if new.item_id<>old.item_id or new.lote is distinct from old.lote or new.caducidad is distinct from old.caducidad or new.costo_unitario<>old.costo_unitario then raise exception 'inventory_lot_identity_is_frozen';end if;
 end if;return new;
end $$;
create trigger inv_product_identity before update on public.inventario for each row execute function private.inv_identity_guard();
create trigger inv_lot_identity before update on public.lotes_inventario for each row execute function private.inv_identity_guard();
-- Clients cannot mutate balances or bypass POS via the legacy table grants/policies.
revoke all on public.inventario,public.lotes_inventario from anon,authenticated;
grant select on public.inventario,public.lotes_inventario to authenticated;
do $$declare p record;t text;begin
 for p in select tablename,policyname from pg_policies where schemaname='public' and tablename in ('inventario','lotes_inventario') loop execute format('drop policy %I on public.%I',p.policyname,p.tablename);end loop;
 foreach t in array array['inventario','lotes_inventario','inventory_clinic_settings','inventory_stock_movements','inventory_cash_shifts','inventory_sales','inventory_sale_lines','inventory_sale_reversals','inventory_cash_movements','inventory_order_drafts','inventory_order_approvals','inventory_vial_links','inventory_dispensing_limits'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy inv_read on public.%I for select to authenticated using (private.inv_access(clinic_id))',t);
 end loop;
 foreach t in array array['inventory_stock_movements','inventory_cash_shifts','inventory_sales','inventory_sale_lines','inventory_sale_reversals','inventory_cash_movements','inventory_order_drafts','inventory_order_approvals','inventory_vial_links','inventory_dispensing_limits'] loop
  execute format('create trigger inv_history before update or delete on public.%I for each row execute function private.inv_history_guard()',t);
 end loop;
end $$;

do $$declare t text;begin
 foreach t in array array['inventory_cash_shifts','inventory_sales','inventory_cash_movements','inventory_sale_reversals'] loop
 execute format('drop policy inv_read on public.%I',t);
 end loop;
end $$;
create policy inv_cash_read on public.inventory_cash_shifts for select to authenticated using(private.has_clinic_role(clinic_id,array['admin']) or (cashier_id=auth.uid() and private.inv_access(clinic_id)));
create policy inv_sale_read on public.inventory_sales for select to authenticated using(private.has_clinic_role(clinic_id,array['admin']) or (cashier_id=auth.uid() and private.inv_access(clinic_id)));
create policy inv_move_read on public.inventory_cash_movements for select to authenticated using(exists(select 1 from public.inventory_cash_shifts sh where sh.id=shift_id and (private.has_clinic_role(sh.clinic_id,array['admin']) or (sh.cashier_id=auth.uid() and private.inv_access(sh.clinic_id)))));
create policy inv_reverse_read on public.inventory_sale_reversals for select to authenticated using(exists(select 1 from public.inventory_cash_shifts sh where sh.id=shift_id and (private.has_clinic_role(sh.clinic_id,array['admin']) or (sh.cashier_id=auth.uid() and private.inv_access(sh.clinic_id)))));
drop policy inv_read on public.inventory_sale_lines;
create policy inv_line_read on public.inventory_sale_lines for select to authenticated using(exists(select 1 from public.inventory_sales s where s.id=sale_id and (private.has_clinic_role(s.clinic_id,array['admin']) or (s.cashier_id=auth.uid() and private.inv_access(s.clinic_id)))));
create function public.inv_dispensing_authorize(p_item uuid,p_rx uuid,p_quantity text,p_until timestamptz,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;r public.prescriptions;x public.prescription_items;v_id uuid;fp jsonb;n numeric;
begin
 select * into i from public.inventario where id=p_item for update;
 select * into x from public.prescription_items where id=p_rx;
 select * into r from public.prescriptions where id=x.prescription_id and clinic_id=i.clinic_id and state='issued';
 if i.id is null or i.m8_kind<>'farmaco' or i.medication_version_id<>x.product_version_id or r.id is null or r.responsible_id<>auth.uid() or not private.rx_professional(i.clinic_id,auth.uid()) then raise exception 'dispensing_limit_responsible_required';end if;
 n=private.inv_quantity(p_quantity,true);
 if p_until is null or p_until<=clock_timestamp() or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'dispensing_limit_fields_required';end if;
 fp=jsonb_build_object('kind','dispensing_limit','item',p_item,'rx',p_rx,'quantity',p_quantity,'until',p_until,'reason',p_reason);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_dispensing_limits(clinic_id,item_id,prescription_item_id,quantity,valid_until,reason,created_by) values(i.clinic_id,i.id,x.id,n,p_until,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_dispensing_limit_authorized',v_id);return v_id;
end $$;
create function public.inv_settings(p_clinic uuid,p_timezone text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'inventory_admin_required';end if;
 if not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'timezone_required';end if;
 insert into public.inventory_clinic_settings values(p_clinic,p_timezone) on conflict(clinic_id) do update set timezone=excluded.timezone;
 insert into public.audit_log(clinic_id,actor_id,action) values(p_clinic,auth.uid(),'inventory_timezone_changed');
end $$;
create function public.inv_product_save(p_clinic uuid,p_id uuid,p_version integer,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;v_id uuid;fp jsonb;price numeric;cost numeric;minimum numeric;reorder numeric;kind text;unit text;med uuid;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'inventory_admin_required';end if;
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
create function public.inv_enable_legacy(p_id uuid,p_kind text,p_unit text,p_medication uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;fp jsonb;v_id uuid;
begin
 select * into i from public.inventario where id=p_id for update;
 if not found or not private.has_clinic_role(i.clinic_id,array['admin']) then raise exception 'inventory_admin_required';end if;
 fp=jsonb_build_object('kind','enable_legacy','item',p_id,'type',p_kind,'unit',p_unit,'medication',p_medication);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if i.m8_enabled then raise exception 'legacy_already_enabled';end if;
 if p_kind not in ('producto','farmaco') or p_unit not in ('unidad','frasco','caja','g','kg','ml','L') or (p_kind='producto' and p_medication is not null) then raise exception 'product_kind_unit_required';end if;
 if i.stock<0 or i.stock<>(select coalesce(sum(cantidad),0) from public.lotes_inventario where item_id=i.id) then raise exception 'legacy_stock_reconciliation_required';end if;
 perform private.inv_money(i.precio_compra::text);perform private.inv_money(i.precio_venta::text);
 for l in select * from public.lotes_inventario where item_id=i.id order by id for update loop
  if l.cantidad<0 or nullif(btrim(l.lote),'') is null then raise exception 'legacy_lot_review_required';end if;
  perform private.inv_money(l.costo_unitario::text);
  if l.cantidad>0 then insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,created_by) values(i.clinic_id,i.id,l.id,l.cantidad,'apertura',l.costo_unitario,'Saldo histórico revisado por admin',auth.uid());end if;
 end loop;
 update public.inventario set m8_enabled=true,m8_kind=p_kind,stock_unit=p_unit,medication_version_id=p_medication,reorder_point=greatest(stock_minimo,reorder_point),version=version+1 where id=i.id;
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,i.id);return i.id;
end $$;
create function public.inv_lot_receive(p_item uuid,p_lot text,p_expiry date,p_quantity text,p_cost text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;v_id uuid;n numeric;cost numeric;fp jsonb;
begin
 select * into i from public.inventario where id=p_item for update;
 if not found or not i.m8_enabled or not private.has_clinic_role(i.clinic_id,array['admin']) then raise exception 'inventory_admin_required';end if;
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
create function public.inv_stock_adjust(p_lot uuid,p_delta text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;
begin
 select * into l from public.lotes_inventario where id=p_lot;
 select * into i from public.inventario where id=l.item_id for update;
 select * into l from public.lotes_inventario where id=p_lot for update;
 if i.id is null or not i.m8_enabled or not private.has_clinic_role(i.clinic_id,array['admin']) then raise exception 'inventory_admin_required';end if;
 if p_delta is null or p_delta !~ '^-?\d{1,12}(\.\d{1,9})?$' or p_delta::numeric=0 or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'adjustment_reason_required';end if;
 n=p_delta::numeric;fp=jsonb_build_object('kind','stock_adjust','lot',p_lot,'delta',p_delta,'reason',p_reason);v_id=private.vet_receipt(i.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if l.cantidad+n<0 or i.stock+n<0 then raise exception 'insufficient_stock';end if;
 update public.lotes_inventario set cantidad=cantidad+n where id=l.id;
 update public.inventario set stock=stock+n,version=version+1 where id=i.id;
 insert into public.inventory_stock_movements(clinic_id,item_id,lot_id,delta,kind,unit_cost,reason,created_by) values(i.clinic_id,i.id,l.id,n,'ajuste',l.costo_unitario,p_reason,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),i.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(i.clinic_id,auth.uid(),'inventory_stock_adjusted',v_id);return v_id;
end $$;
create function public.inv_shift_open(p_clinic uuid,p_opening text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;n numeric;
begin
 if not private.inv_access(p_clinic) then raise exception 'cashier_role_required';end if;
 perform pg_advisory_xact_lock(hashtextextended('inv-shift-'||p_clinic::text||auth.uid()::text,0));
 n=private.inv_money(p_opening);fp=jsonb_build_object('kind','shift_open','opening',p_opening);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_cash_shifts(clinic_id,cashier_id,opening_cash,timezone) values(p_clinic,auth.uid(),n,private.inv_timezone(p_clinic)) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end $$;
create function private.inv_dispense(i public.inventario,p_rx uuid,p_quantity numeric) returns jsonb language plpgsql security definer set search_path='' as $$
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
   if not private.has_clinic_role(i.clinic_id,array['auxiliar']) or not private.rx_case(c) then raise exception 'ordinary_dispensing_delegation_required';end if;
   select * into profile from public.professional_profiles where clinic_id=i.clinic_id and user_id=c.responsible_id for update;
   select * into delegation from public.professional_delegations d where d.profile_id=profile.id and d.recipient_id=auth.uid() and d.case_id=c.id and d.dispense_ordinary and d.valid_until>clock_timestamp() and not exists(select 1 from public.professional_delegation_revocations z where z.delegation_id=d.id) order by d.created_at desc limit 1;
   if delegation.id is null or not private.rx_professional(i.clinic_id,c.responsible_id) then raise exception 'ordinary_dispensing_delegation_required';end if;
  end if;
 end if;
 select * into v_limit from public.inventory_dispensing_limits where item_id=i.id and prescription_item_id=x.id order by created_at desc,id desc limit 1;
 if v_limit.id is null or v_limit.valid_until<=clock_timestamp() or v_limit.quantity<=0 then raise exception 'dispensing_quantity_authorization_required';end if;
 select coalesce(sum(sl.quantity),0) into dispensed from public.inventory_sale_lines sl where sl.item_id=i.id and sl.prescription_item_id=x.id and not exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=sl.sale_id);
 if dispensed+p_quantity>v_limit.quantity then raise exception 'dispensing_authorized_quantity_exceeded';end if;
 return jsonb_build_object('quantity_authorization_id',v_limit.id,'medication_version_id',p.id,'classification',p.classification,'quantified',p.quantified_prescription,'prescription_id',r.id,'folio',r.official_folio,'dispensed_by',auth.uid(),'delegation_id',delegation.id);
end $$;
create function public.inv_sale_post(p_shift uuid,p_method text,p_lines jsonb,p_expected_total text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;i public.inventario;l public.lotes_inventario;x jsonb;v_sale uuid;fp jsonb;n numeric;total numeric=0;cost numeric=0;commission numeric=0;line_total numeric;line_cost numeric;line_commission numeric;meta jsonb;name text;price numeric;prof uuid;rx uuid;v_item uuid;
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
 v_sale=gen_random_uuid();
 for x in select * from jsonb_array_elements(p_lines) loop
  n=private.inv_quantity(x->>'quantity');meta='{}';prof=null;rx=null;
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
  insert into public.inventory_sale_lines(sale_id,clinic_id,kind,item_id,lot_id,prescription_item_id,name,lot,quantity,stock_unit,price,cost,total,commission,professional_id,metadata)
  values(v_sale,sh.clinic_id,x->>'kind',case when x->>'kind'='producto' then i.id end,case when x->>'kind'='producto' then l.id end,rx,name,case when x->>'kind'='producto' then l.lote end,n,case when x->>'kind'='producto' then i.stock_unit else 'servicio' end,price,line_cost,line_total,line_commission,prof,meta);
 end loop;
 if total<=0 or total<>private.inv_money(p_expected_total) then raise exception 'sale_total_changed';end if;
 insert into public.inventory_sales(id,clinic_id,shift_id,cashier_id,method,total,cost,commission) values(v_sale,sh.clinic_id,sh.id,auth.uid(),p_method,total,cost,commission);
 insert into private.vet_operation_receipts values(auth.uid(),sh.clinic_id,p_operation,fp,v_sale);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(sh.clinic_id,auth.uid(),'inventory_sale_posted',v_sale);return v_sale;
end $$;
create function public.inv_sale_reverse(p_sale uuid,p_shift uuid,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.inventory_sales;sh public.inventory_cash_shifts;x public.inventory_sale_lines;v_id uuid;fp jsonb;key uuid;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift for update;
 select * into s from public.inventory_sales where id=p_sale and clinic_id=sh.clinic_id for update;
 if s.id is null or sh.cashier_id<>auth.uid() or not private.has_clinic_role(sh.clinic_id,array['admin']) then raise exception 'reversal_admin_own_shift_required';end if;
 fp=jsonb_build_object('kind','reverse','sale',p_sale,'shift',p_shift,'reason',p_reason);v_id=private.vet_receipt(sh.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 if sh.closed_at is not null then raise exception 'closed_shift';end if;
 if exists(select 1 from public.inventory_sale_reversals where sale_id=s.id) then raise exception 'sale_already_reversed';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'reversal_reason_required';end if;
 if exists(select 1 from public.inventory_sale_lines where sale_id=s.id and (metadata->>'classification'<>'no_controlado' or metadata->>'quantified'='true')) and not private.rx_professional(sh.clinic_id,auth.uid()) then raise exception 'controlled_reversal_professional_only';end if;
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
create function public.inv_cash_move(p_shift uuid,p_kind text,p_amount text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;v_id uuid;fp jsonb;n numeric;
begin
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
create function private.inv_totals(clinic uuid,shift uuid,start_time timestamptz,end_time timestamptz) returns jsonb language sql stable security definer set search_path='' as $$
 with flows as (
 select s.id,s.method,s.total,s.cost,s.commission from public.inventory_sales s where s.clinic_id=$1 and ($2 is null or s.shift_id=$2) and ($3 is null or s.created_at>=$3) and ($4 is null or s.created_at<$4)
 union all select s.id,s.method,-s.total,-s.cost,-s.commission from public.inventory_sale_reversals r join public.inventory_sales s on s.id=r.sale_id where r.clinic_id=$1 and ($2 is null or r.shift_id=$2) and ($3 is null or r.created_at>=$3) and ($4 is null or r.created_at<$4)),
 money as (select coalesce(sum(total),0) gross,coalesce(sum(cost),0) cost,coalesce(sum(commission),0) commission,coalesce(sum(total) filter(where method='efectivo'),0) cash,coalesce(sum(total) filter(where method='tarjeta'),0) card,coalesce(sum(total) filter(where method='transferencia'),0) transfer from flows),
 cashmoves as (select coalesce(sum(amount) filter(where kind='ingreso'),0) income,coalesce(sum(amount) filter(where kind='retiro'),0) withdrawal,coalesce(sum(amount) filter(where kind='gasto'),0) expense from public.inventory_cash_movements m where m.clinic_id=$1 and ($2 is null or m.shift_id=$2) and ($3 is null or m.created_at>=$3) and ($4 is null or m.created_at<$4))
 select jsonb_build_object('gross',gross::text,'cost',cost::text,'commission',commission::text,'margin',(gross-cost-commission)::text,'recorded_net',(gross-cost-commission-expense)::text,'cash',cash::text,'card',card::text,'transfer',transfer::text,'income',income::text,'withdrawal',withdrawal::text,'expense',expense::text) from money,cashmoves;
$$;
create function public.inv_shift_snapshot(p_shift uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;totals jsonb;
begin
 select * into sh from public.inventory_cash_shifts where id=p_shift;
 if not found or not private.inv_access(sh.clinic_id) or (sh.cashier_id<>auth.uid() and not private.has_clinic_role(sh.clinic_id,array['admin'])) then raise exception 'shift_access_required';end if;
 if sh.closed_at is not null then return sh.snapshot;end if;
 totals=private.inv_totals(sh.clinic_id,sh.id,null,null);
 return jsonb_build_object('shift_id',sh.id,'clinic_id',sh.clinic_id,'cashier_id',sh.cashier_id,'opened_at',sh.opened_at,'timezone',sh.timezone,'cutoff',clock_timestamp(),'opening_cash',sh.opening_cash::text,'totals',totals,
 'expected_cash',(sh.opening_cash+(totals->>'cash')::numeric+(totals->>'income')::numeric-(totals->>'withdrawal')::numeric-(totals->>'expense')::numeric)::text,
 'sales',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('total',s.total::text,'cost',s.cost::text,'commission',s.commission::text,'lines',(select jsonb_agg(to_jsonb(l)||jsonb_build_object('quantity',l.quantity::text,'price',l.price::text,'total',l.total::text,'cost',l.cost::text,'commission',l.commission::text)) from public.inventory_sale_lines l where sale_id=s.id))) from public.inventory_sales s where shift_id=sh.id),'[]'),
 'reversals',coalesce((select jsonb_agg(to_jsonb(r)) from public.inventory_sale_reversals r where shift_id=sh.id),'[]'),
 'cash_movements',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('amount',m.amount::text)) from public.inventory_cash_movements m where shift_id=sh.id),'[]'));
end $$;
create function public.inv_shift_close(p_shift uuid,p_counted text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare sh public.inventory_cash_shifts;v_snapshot jsonb;n numeric;difference numeric;fp jsonb;v_id uuid;
begin
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
create function public.inv_dashboard(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text;today date;start_at timestamptz;end_at timestamptz;
begin
 if not private.inv_access(p_clinic) then raise exception 'inventory_access_required';end if;
 tz=private.inv_timezone(p_clinic);today=(clock_timestamp() at time zone tz)::date;start_at=today::timestamp at time zone tz;end_at=(today+1)::timestamp at time zone tz;
 return jsonb_build_object('professional',private.rx_professional(p_clinic,auth.uid()),'timezone',tz,'today',today,'server_time',clock_timestamp(),
 'products',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('stock',i.stock::text,'stock_minimo',i.stock_minimo::text,'reorder_point',i.reorder_point::text,'precio_compra',i.precio_compra::text,'precio_venta',i.precio_venta::text,'available_stock',available::text,'low_stock',available<=i.stock_minimo,'reorder',available<=i.reorder_point,'lots',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('cantidad',l.cantidad::text,'costo_unitario',l.costo_unitario::text,'days',l.caducidad-today,'expired',l.caducidad<=today) order by l.caducidad nulls last,l.created_at) from public.lotes_inventario l where item_id=i.id),'[]')) order by i.nombre) from public.inventario i cross join lateral(select coalesce(sum(l.cantidad),0) available from public.lotes_inventario l where l.item_id=i.id and (l.caducidad>today or (l.caducidad is null and i.m8_kind='producto'))) a where i.clinic_id=p_clinic),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(sh)-'snapshot'||jsonb_build_object('opening_cash',sh.opening_cash::text,'counted_cash',sh.counted_cash::text) order by sh.opened_at desc) from public.inventory_cash_shifts sh where clinic_id=p_clinic and (cashier_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),'[]'),
 'day_totals',case when private.has_clinic_role(p_clinic,array['admin']) then private.inv_totals(p_clinic,null,start_at,end_at) else null end,
 'catalog',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'presentation',p.presentation,'classification',p.classification,'source_status',p.source_status)) from public.medication_product_versions p where p.version=(select max(v.version) from public.medication_product_versions v where v.product_key=p.product_key)),'[]'),
 'staff',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'role',m.role,'label',coalesce(u.email,m.user_id::text))) from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=p_clinic),'[]'),
 'prescription_items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'product_version_id',x.product_version_id,'prescription_id',r.id,'folio',r.official_folio,'patient_id',r.patient_id)) from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.clinic_id=p_clinic and r.state='issued' and (private.rx_professional(p_clinic,auth.uid()) or (not r.controlled and exists(select 1 from public.clinical_cases c where c.id=r.case_id and private.rx_case(c))))),'[]'),
 'top_products',case when private.has_clinic_role(p_clinic,array['admin']) then coalesce((
 select jsonb_agg(jsonb_build_object('id',x.item_id,'name',i.nombre,'unit',i.stock_unit,'quantity',x.quantity::text,'amount',x.amount::text) order by x.amount desc) from (
 select f.item_id,sum(f.quantity) quantity,sum(f.amount) amount from (
 select l.item_id,l.quantity,l.total amount from public.inventory_sale_lines l join public.inventory_sales s on s.id=l.sale_id where l.clinic_id=p_clinic and l.kind='producto' and s.created_at>=start_at-interval '29 days' and s.created_at<end_at
 union all select l.item_id,-l.quantity,-l.total from public.inventory_sale_lines l join public.inventory_sale_reversals r on r.sale_id=l.sale_id where l.clinic_id=p_clinic and l.kind='producto' and r.created_at>=start_at-interval '29 days' and r.created_at<end_at
 ) f group by f.item_id having sum(f.amount)>0 order by sum(f.amount) desc limit 10) x join public.inventario i on i.id=x.item_id),'[]') else '[]'::jsonb end,
 'orders',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('approval',(select to_jsonb(a) from public.inventory_order_approvals a where draft_id=d.id)) order by d.created_at desc) from public.inventory_order_drafts d where clinic_id=p_clinic),'[]'));
end $$;
create function public.inv_order_draft(p_clinic uuid,p_supplier text,p_message text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;fp jsonb;
begin
 if not private.has_clinic_role(p_clinic,array['admin']) then raise exception 'inventory_admin_required';end if;
 if coalesce(length(btrim(p_supplier)),0) not between 1 and 200 or coalesce(length(btrim(p_message)),0) not between 1 and 8000 then raise exception 'order_fields_required';end if;
 fp=jsonb_build_object('kind','order','supplier',p_supplier,'message',p_message);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_order_drafts(clinic_id,supplier,message,created_by) values(p_clinic,btrim(p_supplier),p_message,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);return v_id;
end $$;
create function public.inv_order_approve(p_id uuid,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.inventory_order_drafts;v_id uuid;fp jsonb;
begin
 select * into d from public.inventory_order_drafts where id=p_id for update;
 if not found or not private.has_clinic_role(d.clinic_id,array['admin']) then raise exception 'inventory_admin_required';end if;
 fp=jsonb_build_object('kind','approve_order','draft',p_id);v_id=private.vet_receipt(d.clinic_id,p_operation,fp);if v_id is not null then return v_id;end if;
 insert into public.inventory_order_approvals(draft_id,clinic_id,approved_by) values(d.id,d.clinic_id,auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),d.clinic_id,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(d.clinic_id,auth.uid(),'inventory_order_approved',d.id);return v_id;
end $$;
create function public.inv_vial_link(p_vial uuid,p_lot uuid,p_packages text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.medication_vials;i public.inventario;l public.lotes_inventario;n numeric;v_id uuid;fp jsonb;
begin
 select * into v from public.medication_vials where id=p_vial;
 if not found or v.responsible_id<>auth.uid() or not private.rx_professional(v.clinic_id,auth.uid()) then raise exception 'vial_responsible_required';end if;
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
-- Tight public API only. Storage photo policies are a separate optional adaptation.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' or n.nspname='private') and p.proname like 'inv_%' loop execute format('revoke all on function %s from public,anon,authenticated',f.signature);end loop;
end $$;
grant execute on function private.inv_access(uuid) to authenticated;
grant execute on function public.inv_dispensing_authorize(uuid,uuid,text,timestamptz,text,text),public.inv_settings(uuid,text),public.inv_product_save(uuid,uuid,integer,jsonb,text),public.inv_enable_legacy(uuid,text,text,uuid,text),public.inv_lot_receive(uuid,text,date,text,text,text),public.inv_stock_adjust(uuid,text,text,text),public.inv_shift_open(uuid,text,text),public.inv_sale_post(uuid,text,jsonb,text,text),public.inv_sale_reverse(uuid,uuid,text,text),public.inv_cash_move(uuid,text,text,text,text),public.inv_shift_snapshot(uuid),public.inv_shift_close(uuid,text,text,text),public.inv_dashboard(uuid),public.inv_order_draft(uuid,text,text,text),public.inv_order_approve(uuid,text),public.inv_vial_link(uuid,uuid,text,text) to authenticated;
commit;
