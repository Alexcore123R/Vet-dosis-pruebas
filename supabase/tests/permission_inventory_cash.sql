-- Synthetic accounting only. No production clinical/financial records.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('test.clinic',:'clinic',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic',auth.uid(),'inventory.read',null,clock_timestamp()+interval '1 day','Synthetic management read');
select pg_temp.assert_true(public.inv_dashboard(:'clinic')->'day_totals'='null'::jsonb,'admin role reads finances');
select pg_temp.expect_error($q$select public.inv_settings(current_setting('test.clinic')::uuid,'UTC')$q$,'explicit_permission_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.manage',null,clock_timestamp()+interval '1 day','Synthetic catalog') as manage_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_product_save(:'clinic',null,0,'{"name":"Synthetic explicit product","presentation":"Synthetic unit","kind":"producto","unit":"unidad","price":"10","cost":"2","minimum":"0","reorder":"0"}',repeat('1521',12)) as item \gset
select set_config('test.item',:'item',false);
select pg_temp.assert_true((public.inv_management_permissions(:'clinic')->'actions'->>'inventory.manage')::boolean,'visual stylist cannot manage with grant');
select pg_temp.assert_true(not(public.inv_management_permissions(:'clinic')->'actions'->>'sales.collect')::boolean,'manage grants collection');
select pg_temp.expect_error($q$select public.inv_lot_receive(current_setting('test.item')::uuid,'SYNTHETIC',current_date+90,'4','2',repeat('1522',12))$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.inv_shift_open(current_setting('test.clinic')::uuid,'0',repeat('1523',12))$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.inv_order_draft(current_setting('test.clinic')::uuid,'Synthetic supplier','Synthetic order',repeat('1524',12))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.receive',null,clock_timestamp()+interval '1 day','Synthetic receiving') as receive_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','sales.collect',null,clock_timestamp()+interval '1 day','Synthetic cashier') as collect_grant \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.order.prepare',null,clock_timestamp()+interval '1 day','Synthetic order');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_lot_receive(:'item','SYNTHETIC-EXPLICIT-CASH',current_date+90,'4','2',repeat('1522',12)) as lot \gset
select set_config('test.lot',:'lot',false);
select pg_temp.expect_error($q$select public.inv_stock_adjust(current_setting('test.lot')::uuid,'1','Synthetic adjustment',repeat('1525',12))$q$,'explicit_permission_required');
select public.inv_order_draft(:'clinic','Synthetic supplier','Synthetic order',repeat('1524',12)) as draft \gset
select set_config('test.draft',:'draft',false);
select pg_temp.expect_error($q$select public.inv_order_approve(current_setting('test.draft')::uuid,repeat('1526',12))$q$,'explicit_permission_required');
select public.inv_shift_open(:'clinic','0',repeat('1523',12)) as shift \gset
select set_config('test.shift',:'shift',false);
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'item','lot_id',:'lot','quantity','1','price','10')),'10',repeat('1527',12)) as sale \gset
select set_config('test.sale',:'sale',false);
select pg_temp.assert_true((public.inv_shift_snapshot(:'shift')->'totals'->>'gross')::numeric=10,'cashier own cut invalid');
select pg_temp.expect_error($q$select public.inv_cash_move(current_setting('test.shift')::uuid,'retiro','1','Synthetic withdrawal',repeat('1528',12))$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.inv_sale_reverse(current_setting('test.sale')::uuid,current_setting('test.shift')::uuid,'Synthetic reversal',repeat('1529',12))$q$,'explicit_permission_required');
select pg_temp.assert_true((select count(*)=1 from public.inventory_cash_shifts),'cashier sees other shifts through table');
select pg_temp.assert_true((select count(*)=0 from public.inventory_sale_lines),'raw cash lines bypass sanitized RPC');
select pg_temp.expect_error($q$select snapshot from public.inventory_cash_shifts$q$,'permission denied');
-- Billing tickets contain no prescription/patient reference even to inventory managers.
select pg_temp.assert_true((public.inv_workflow_dashboard(:'clinic')->'deliveries'->0->'reference')='{}'::jsonb,'billing leaked clinical reference');
select pg_temp.assert_true((select count(*)=0 from public.inventory_delivery_tickets),'raw delivery reference leaked to cashier');
select pg_temp.expect_error($q$update public.lotes_inventario set cantidad=900 where id=current_setting('test.lot')::uuid$q$,'permission denied');
reset role;
-- Separate permissions allow each operation without changing a visual job.
reset role;
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.adjust',null,clock_timestamp()+interval '1 day','Synthetic adjustment');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','cash.move',null,clock_timestamp()+interval '1 day','Synthetic cash movement');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','sales.reverse',null,clock_timestamp()+interval '1 day','Synthetic reversal');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.order.approve',null,clock_timestamp()+interval '1 day','Synthetic order approval');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_stock_adjust(:'lot','1','Synthetic audited adjustment',repeat('1541',12));
select public.inv_cash_move(:'shift','ingreso','1','Synthetic audited income',repeat('1542',12));
select public.inv_sale_reverse(:'sale',:'shift','Synthetic audited reversal',repeat('1543',12));
select public.inv_order_approve(:'draft',repeat('1526',12));
select pg_temp.assert_true((select cantidad=5 from public.lotes_inventario where id=:'lot'),'adjustment/reversal stock incorrect');
select pg_temp.assert_true((public.inv_shift_snapshot(:'shift')->'totals'->>'gross')::numeric=0,'reversal did not reverse money');
rollback;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
-- Manual billing is distinct from collection, including receipt replay.
reset role;
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','sales.manual',null,clock_timestamp()+interval '1 day','Synthetic manual billing') as manual_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_sale_post(:'shift','efectivo','[{"kind":"servicio","name":"Synthetic billing only","quantity":"1","price":"1","cost":"0","commission":"0"}]','1',repeat('1545',12));
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'manual_grant','Synthetic manual revoked');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.inv_sale_post(current_setting('test.shift')::uuid,'efectivo','[{"kind":"servicio","name":"Synthetic billing only","quantity":"1","price":"1","cost":"0","commission":"0"}]','1',repeat('1545',12))$q$,'explicit_permission_required');
rollback;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
-- The dispensing guard survives the cash cut; collection does not grant delivery.
reset role;
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','controlled.dispense',null,clock_timestamp()+interval '1 day','Synthetic post-cut dispensing');
reset role;
update public.clinic_members set role='estilista' where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000151';
select id as drug_item from public.inventario where nombre='Synthetic dispensing ordinary' \gset
select id as drug_lot from public.lotes_inventario where item_id=:'drug_item' \gset
select x.id as drug_rxitem from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.instructions='Synthetic standing' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_dispensing_authorize(:'drug_item',:'drug_rxitem','3',clock_timestamp()+interval '1 hour','Synthetic post-cut stock amount',repeat('1551',12));
select public.inv_delivery_prepare(:'drug_lot',:'drug_rxitem','1',repeat('1552',12)) as clinical_delivery \gset
reset role;
select set_config('test.drug_item',:'drug_item',true),set_config('test.drug_lot',:'drug_lot',true),set_config('test.drug_rxitem',:'drug_rxitem',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','delivery_id',:'clinical_delivery','quantity','1','price','10')),'10',repeat('1553',12));
select pg_temp.expect_error($q$select public.inv_sale_post(current_setting('test.shift')::uuid,'efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.drug_item'),'lot_id',current_setting('test.drug_lot'),'prescription_item_id',current_setting('test.drug_rxitem'),'quantity','1','price','10')),'10',repeat('1554',12))$q$,'verified_dispensing_permission_required');
reset role;
select pg_temp.assert_true((select cantidad=7 from public.lotes_inventario where id=:'drug_lot'),'collection moved another drug unit');
rollback;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
-- Catalog edits keep optimistic version checks, independent of receiving stock.
begin;
select version as original_product_version from public.inventario where id=:'item' \gset
select set_config('test.original_product_version',:'original_product_version',true);
select public.inv_product_save(:'clinic',:'item',:'original_product_version','{"name":"Synthetic explicit product","presentation":"Synthetic unit","kind":"producto","unit":"unidad","price":"11","cost":"2","minimum":"0","reorder":"0"}',repeat('1548',12));
select pg_temp.expect_error($q$select public.inv_product_save(current_setting('test.clinic')::uuid,current_setting('test.item')::uuid,current_setting('test.original_product_version')::integer,'{"name":"Synthetic explicit product","presentation":"Synthetic unit","kind":"producto","unit":"unidad","price":"11","cost":"2","minimum":"0","reorder":"0"}',repeat('1549',12))$q$,'product_revision_conflict_or_legacy');
rollback;
-- Storage read/write and attachment use the same explicit catalog permission.
select :'clinic'||'/'||:'item'||'/'||repeat('15aa',12)||'.jpg' as photo_path \gset
insert into storage.objects(bucket_id,name) values('inventory-photos',:'photo_path');
select version as product_version from public.inventario where id=:'item' \gset
select public.inv_photo_attach(:'item',:'product_version',:'photo_path');
select set_config('test.photo_path',:'photo_path',false);
reset role;
-- An immutable old cut may contain clinical reference: sanitization does not modify it.
update public.inventory_cash_shifts set snapshot='{"sales":[{"lines":[{"name":"Synthetic private application","application_charge_id":"00000000-0000-0000-0000-000000000999","metadata":{"patient_name":"Synthetic private patient"},"prescription_item_id":"00000000-0000-0000-0000-000000000999"}]}]}',closed_at=clock_timestamp() where id=:'shift';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true((public.inv_shift_snapshot(:'shift')->'sales'->0->'lines'->0->'metadata')='{}'::jsonb,'closed cut leaked clinical metadata');
select pg_temp.assert_true((public.inv_shift_snapshot(:'shift')->'sales'->0->'lines'->0->>'name')='Cargo por aplicación','closed cut leaked application');
reset role;
select pg_temp.assert_true((select snapshot->'sales'->0->'lines'->0->'metadata'->>'patient_name'='Synthetic private patient' from public.inventory_cash_shifts where id=:'shift'),'sanitization rewrote frozen cut');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic',auth.uid(),'sales.read',null,clock_timestamp()+interval '1 day','Synthetic finance reader');
select pg_temp.assert_true((select count(*)>1 from public.inventory_cash_shifts),'finance grant cannot read other cuts');
select public.permission_revoke(:'manage_grant','Synthetic revoked catalog');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.expect_error($q$select public.inv_product_save(current_setting('test.clinic')::uuid,null,0,'{}',repeat('1521',12))$q$,'explicit_permission_required');
select pg_temp.expect_error($q$insert into storage.objects(bucket_id,name) values('inventory-photos',replace(current_setting('test.photo_path'),repeat('15aa',12),repeat('15bb',12)))$q$,'row-level security');
-- External references are observational, with a distinct reconciliation grant.
select public.pay_report(:'clinic',jsonb_build_object('sale_id',:'sale','direction','ingreso','method','efectivo','amount','10','provider','Synthetic observation only','occurred_at',clock_timestamp()),repeat('1561',12)) as payment \gset
select set_config('test.payment',:'payment',false);
select pg_temp.expect_error($q$select public.pay_reconcile(current_setting('test.payment')::uuid,'verificada','0','Synthetic verification',repeat('1562',12))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.expect_error($q$select public.pay_reconcile(current_setting('test.payment')::uuid,'verificada','0','Synthetic verification',repeat('1562',12))$q$,'explicit_permission_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','sales.reconcile',null,clock_timestamp()+interval '1 day','Synthetic reconciliation');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','sales.read',null,clock_timestamp()+interval '1 day','Synthetic finance reading');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.pay_reconcile(:'payment','verificada','0','Synthetic verification',repeat('1562',12));
select public.pay_reconcile(:'payment','verificada','0','Synthetic verification',repeat('1562',12));
select pg_temp.assert_true(public.pay_dashboard(:'clinic')->'transactions'->0->>'state'='verificada','reconciliation did not append status');
select pg_temp.assert_true((select cantidad=3 from public.lotes_inventario where id=:'lot'),'payment reference moved stock');
reset role;
select pg_temp.assert_true(exists(select 1 from public.audit_log where action='inventory_permission_used' and details->>'operation'=repeat('1527',12) and details->>'code'='sales.collect' and details->>'grant_id'=:'collect_grant'),'permission receipt not auditable');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.inventario),'foreign inventory leak');
select pg_temp.assert_true((select count(*)=0 from public.inventory_cash_shifts),'foreign cash leak');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='inventory-photos'),'foreign photo leak');
select pg_temp.expect_error($q$select public.inv_dashboard(current_setting('test.clinic')::uuid)$q$,'inventory_access_required');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.inv_management_permissions(current_setting('test.clinic')::uuid)$q$,'permission denied');
reset role;
