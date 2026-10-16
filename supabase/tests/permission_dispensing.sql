-- Fictitious products/accounting only; no clinical or legal values imported.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as product from public.medication_product_versions where product_key='synthetic-prescription-workflow' \gset
select x.id as rxitem from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.instructions='Synthetic standing' \gset
select set_config('test.clinic',:'clinic',false),set_config('test.rxitem',:'rxitem',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','inventory.read',null,clock_timestamp()+interval '1 day','Synthetic dispensing read');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.read',null,clock_timestamp()+interval '1 day','Synthetic dispensing read');
select public.inv_product_save(:'clinic',null,0,jsonb_build_object('name','Synthetic dispensing ordinary','presentation','Synthetic','kind','farmaco','unit','frasco','medication_version_id',:'product','price','10','cost','2','minimum','0','reorder','0'),repeat('1411',12)) as item \gset
select public.inv_lot_receive(:'item','SYNTHETIC-DISPENSING',current_date+90,'10','2',repeat('1412',12)) as lot \gset
select set_config('test.item',:'item',false),set_config('test.lot',:'lot',false);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true(not(public.inv_dispensing_permissions(:'clinic')->>'can_dispense')::boolean,'verified profile without grant can dispense');
select pg_temp.expect_error($q$select public.inv_delivery_prepare(current_setting('test.lot')::uuid,current_setting('test.rxitem')::uuid,'1',repeat('1413',12))$q$,'verified_dispensing_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','controlled.dispense',null,clock_timestamp()+interval '1 day','Synthetic dispensing') as dispensing_grant \gset
select pg_temp.expect_error($q$select public.permission_grant(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000170','controlled.dispense',null,clock_timestamp()+interval '1 day','Synthetic unverified')$q$,'verified_professional_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_dispensing_authorize(:'item',:'rxitem','3',clock_timestamp()+interval '1 day','Synthetic stock units, not a dose',repeat('1414',12)) as quantity_limit \gset
select public.inv_delivery_prepare(:'lot',:'rxitem','1',repeat('1415',12)) as delivery \gset
select public.inv_delivery_prepare(:'lot',:'rxitem','1',repeat('1415',12));
select set_config('test.delivery',:'delivery',false);
reset role;
select pg_temp.assert_true((select cantidad=9 from public.lotes_inventario where id=:'lot'),'receipt delivered twice');
select pg_temp.assert_true((select reference->>'dispense_grant_id'=:'dispensing_grant' and reference->>'limit_permission_grant_id'=:'dispensing_grant' from public.inventory_delivery_tickets where id=:'delivery'),'authority trace lost');
-- An old untyped quantity is preserved as history and needs explicit review.
begin;
insert into public.inventory_dispensing_limits(clinic_id,item_id,prescription_item_id,quantity,valid_until,reason,created_by)
values(:'clinic',:'item',:'rxitem',3,clock_timestamp()+interval '1 day','Synthetic legacy quantity','00000000-0000-0000-0000-000000000151');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.inv_delivery_prepare(current_setting('test.lot')::uuid,current_setting('test.rxitem')::uuid,'1',repeat('1447',12))$q$,'dispensing_limit_reauthorization_required');
rollback;
-- Profile version is part of the authorization; a new version needs review.
begin;
insert into private.professional_profile_versions(profile_id,version,name,license,registration,signature,created_by)
select v.profile_id,v.version+1,v.name,v.license,v.registration,v.signature,v.created_by from private.professional_profile_versions v
where v.id=(select profile_version_id from public.inventory_dispensing_limits where id=:'quantity_limit');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.inv_delivery_prepare(current_setting('test.lot')::uuid,current_setting('test.rxitem')::uuid,'1',repeat('1447',12))$q$,'dispensing_limit_authority_changed');
rollback;
-- Changing the visual job never changes authority.
begin;
update public.clinic_members set role='estilista' where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000151';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true((public.inv_dispensing_permissions(:'clinic')->>'can_dispense')::boolean,'visual job revoked explicit professional permission');
select public.inv_delivery_prepare(:'lot',:'rxitem','1',repeat('1415',12));
rollback;
-- A controlled reference must still use an issued individual prescription.
begin;
select id as controlled_product from public.medication_product_versions where product_key='synthetic-controlled-workflow' \gset
select id as controlled_rx from public.prescriptions where instructions='Synthetic controlled instructions' \gset
select id as controlled_rxitem from public.prescription_items where prescription_id=:'controlled_rx' \gset
select name as responsible_name from private.professional_profile_versions where id=(select authorization_profile_version_id from public.prescriptions where id=:'controlled_rx') \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_return_to_draft(:'controlled_rx',3,'Synthetic current format');
select public.rx_consultation_sign(:'controlled_rx',4,:'responsible_name','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1441',12)) as control_signature \gset
select public.rx_prepare_attributed(:'controlled_rx',4,:'control_signature',:'responsible_name');
select public.rx_authorize_individual(:'controlled_rx',5,true);
select public.rx_pdf_snapshot('prescription',:'controlled_rx')->>'content_hash' as control_hash \gset
reset role;
set role service_role;
select public.rx_pdf_register('prescription',:'controlled_rx',6,:'control_hash',encode(convert_to('%PDF-SYNTHETIC-CONTROLLED-DISPENSING','UTF8'),'base64'),'iVBORw0KGgo=')->>'hash' as control_pdf \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_finalize(:'controlled_rx',6,:'control_pdf');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.inv_product_save(:'clinic',null,0,jsonb_build_object('name','Synthetic controlled dispensing','presentation','Synthetic','kind','farmaco','unit','frasco','medication_version_id',:'controlled_product','price','10','cost','2','minimum','0','reorder','0'),repeat('1442',12)) as control_item \gset
select public.inv_lot_receive(:'control_item','SYNTHETIC-CONTROL-DISPENSING',current_date+90,'2','2',repeat('1443',12)) as control_lot \gset
select public.permission_grant(:'clinic',auth.uid(),'inventory.adjust',null,clock_timestamp()+interval '1 day','Synthetic adjustment test');
select set_config('test.control_lot',:'control_lot',true);
select pg_temp.expect_error($q$select public.inv_stock_adjust(current_setting('test.control_lot')::uuid,'1','Synthetic not allowed',repeat('1444',12))$q$,'controlled_or_unverified_stock_adjustment_denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_dispensing_authorize(:'control_item',:'controlled_rxitem','1',clock_timestamp()+interval '1 day','Synthetic control stock unit',repeat('1445',12));
select public.inv_delivery_prepare(:'control_lot',:'controlled_rxitem','1',repeat('1446',12));
rollback;
-- Even a forged old declaration/grant cannot replace professional verification.
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select :'clinic',user_id,created_at,'controlled.dispense','00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day','Synthetic adversarial fixture' from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000170';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select pg_temp.assert_true(public.inv_delivery_items(:'clinic')='[]'::jsonb,'unverified sees dispensing choices');
select pg_temp.expect_error($q$select public.inv_delivery_prepare(current_setting('test.lot')::uuid,current_setting('test.rxitem')::uuid,'1',repeat('1416',12))$q$,'verified_dispensing_permission_required');
select pg_temp.expect_error($q$select public.inv_delivery_grant(current_setting('test.clinic')::uuid,auth.uid(),null,'Synthetic',repeat('1417',12))$q$,'legacy_delivery_delegation_disabled');
reset role;
-- Own authorization cannot become larger by racing a sale and a physical delivery.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_shift_open(:'clinic','0',repeat('1418',12)) as shift \gset
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'item','lot_id',:'lot','quantity','1','price','10','prescription_item_id',:'rxitem')),'10',repeat('1419',12)) as sale \gset
select set_config('test.shift',:'shift',false);
select pg_temp.expect_error($q$select public.inv_delivery_prepare(current_setting('test.lot')::uuid,current_setting('test.rxitem')::uuid,'2',repeat('1420',12))$q$,'dispensing_authorized_quantity_exceeded');
-- Cashier may collect an already delivered drug without a second physical movement.
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.inv_shift_open(:'clinic','0',repeat('1421',12)) as cashier_shift \gset
select public.inv_sale_post(:'cashier_shift','tarjeta',jsonb_build_array(jsonb_build_object('kind','servicio','delivery_id',:'delivery','quantity','1','price','10')),'10',repeat('1422',12));
reset role;
select pg_temp.assert_true((select cantidad=8 from public.lotes_inventario where id=:'lot'),'collection deducted stock');
-- Revocation checked before a receipt is returned, too.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'dispensing_grant','Synthetic revoked');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.inv_delivery_prepare(current_setting('test.lot')::uuid,current_setting('test.rxitem')::uuid,'1',repeat('1415',12))$q$,'verified_dispensing_permission_required');
select pg_temp.expect_error($q$select public.inv_sale_post(current_setting('test.shift')::uuid,'efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.item'),'lot_id',current_setting('test.lot'),'quantity','1','price','10','prescription_item_id',current_setting('test.rxitem'))),'10',repeat('1419',12))$q$,'verified_dispensing_permission_required');
reset role;
set role anon;
select pg_temp.expect_error($q$select public.inv_dispensing_permissions(current_setting('test.clinic')::uuid)$q$,'permission denied');
reset role;
