-- Synthetic accounting/stock fixtures, no real data or regulatory sources.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select clinic_id as clinic from public.clinic_members where user_id=auth.uid() limit 1 \gset
select set_config('test.inv_clinic',:'clinic',true);
select public.inv_product_save(:'clinic',null,0,'{"name":"Producto sintético","presentation":"Unidad ficticia","kind":"producto","unit":"unidad","price":"10.10","cost":"4.00","minimum":"1","reorder":"2","barcode":"SYNTHETIC","supplier":"Proveedor ficticio"}',repeat('a1',24)) as item \gset
select set_config('test.inv_item',:'item',true);
select public.inv_lot_receive(:'item','LOTE-INVENTARIO',current_date+90,'5','4.00',repeat('a2',24)) as lot \gset
select set_config('test.inv_lot',:'lot',true);
select public.inv_lot_receive(:'item','LOTE-CADUCADO',current_date-1,'2','4.00',repeat('a3',24)) as expired \gset
select set_config('test.inv_expired',:'expired',true);
select public.inv_shift_open(:'clinic','100.00',repeat('a4',24)) as shift \gset
select set_config('test.inv_shift',:'shift',true);
select set_config('test.inv_lines',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'item','lot_id',:'lot','quantity','2','price','10.10'))::text,true);
select public.inv_sale_post(:'shift','efectivo',current_setting('test.inv_lines')::jsonb,'20.20',repeat('a5',24)) as sale \gset
select set_config('test.inv_sale',:'sale',true);
select public.inv_sale_post(:'shift','efectivo',current_setting('test.inv_lines')::jsonb,'20.20',repeat('a5',24));
do $$begin
 if (select cantidad from public.lotes_inventario where id=current_setting('test.inv_lot')::uuid)<>3 then raise exception 'Sale retry deducted twice';end if;
 if (select stock from public.inventario where id=current_setting('test.inv_item')::uuid)<>5 then raise exception 'Aggregate balance wrong';end if;
 if (public.inv_shift_snapshot(current_setting('test.inv_shift')::uuid)->>'expected_cash')::numeric<>120.20 then raise exception 'Exact sale money incorrect';end if;
 begin perform public.inv_sale_post(current_setting('test.inv_shift')::uuid,'efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.inv_item'),'lot_id',current_setting('test.inv_expired'),'quantity','1','price','10.10')),'10.10',repeat('a6',24));raise exception 'Expired lot sold';exception when raise_exception then if sqlerrm<>'expired_lot_blocked' then raise;end if;end;
 begin perform public.inv_sale_post(current_setting('test.inv_shift')::uuid,'efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.inv_item'),'lot_id',current_setting('test.inv_lot'),'quantity','4','price','10.10')),'40.40',repeat('a7',24));raise exception 'Oversold stock';exception when raise_exception then if sqlerrm<>'insufficient_stock' then raise;end if;end;
 begin update public.inventario set stock=99;raise exception 'Direct stock mutation';exception when insufficient_privilege then null;end;
end $$;
select public.inv_cash_move(:'shift','gasto','5.00','Gasto sintético',repeat('a8',24));
select public.inv_cash_move(:'shift','retiro','10.00','Retiro sintético',repeat('a9',24));
select public.inv_shift_close(:'shift','105.20','',repeat('b1',24));
select set_config('test.inv_frozen',public.inv_shift_snapshot(:'shift')::text,true);
select public.inv_shift_open(:'clinic','0',repeat('b2',24)) as shift2 \gset
select public.inv_sale_reverse(:'sale',:'shift2','Devolución ficticia',repeat('b3',24));
select public.inv_sale_reverse(:'sale',:'shift2','Devolución ficticia',repeat('b3',24));
do $$begin
 if public.inv_shift_snapshot(current_setting('test.inv_shift')::uuid)<>current_setting('test.inv_frozen')::jsonb then raise exception 'Later reversal changed frozen cut';end if;
 if (select cantidad from public.lotes_inventario where id=current_setting('test.inv_lot')::uuid)<>5 then raise exception 'Reversal failed or doubled';end if;
end $$;
select public.inv_product_save(:'clinic',null,0,'{"name":"Fármaco sintético controlado","presentation":"Frasco ficticio","kind":"farmaco","unit":"frasco","medication_version_id":"10000000-0000-0000-0000-000000000002","price":"100.00","cost":"20.00","minimum":"0","reorder":"1"}',repeat('b4',24)) as drug \gset
select public.inv_lot_receive(:'drug','LOTE-SINTETICO',current_date+90,'4','20.00',repeat('b5',24)) as druglot \gset
select set_config('test.inv_drug',:'drug',true);select set_config('test.inv_druglot',:'druglot',true);
select id as rxitem from public.prescription_items where prescription_id in(select id from public.prescriptions where controlled and state='issued') limit 1 \gset
select set_config('test.inv_rxitem',:'rxitem',true);
select public.inv_dashboard(:'clinic');
select public.inv_order_draft(:'clinic','Proveedor ficticio','Mensaje revisable ficticio',repeat('b6',24)) as draft \gset
select set_config('test.inv_draft',:'draft',true);
select public.inv_order_approve(:'draft',repeat('b7',24));
-- Self-declared admin is not a reviewed professional.
do $$begin
 begin perform public.inv_sale_post((select id from public.inventory_cash_shifts where closed_at is null and cashier_id=auth.uid()),'tarjeta',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.inv_drug'),'lot_id',current_setting('test.inv_druglot'),'quantity','1','price','100.00','prescription_item_id',current_setting('test.inv_rxitem'))),'100.00',repeat('b8',24));raise exception 'Admin dispensed quantified drug';exception when raise_exception then if sqlerrm<>'quantified_dispensing_professional_only' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select public.inv_shift_open(:'clinic','0',repeat('b9',24)) as auxshift \gset
select set_config('test.inv_auxshift',:'auxshift',true);
do $$begin
 begin perform public.inv_sale_post(current_setting('test.inv_auxshift')::uuid,'tarjeta',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.inv_drug'),'lot_id',current_setting('test.inv_druglot'),'quantity','1','price','100.00','prescription_item_id',current_setting('test.inv_rxitem'))),'100.00',repeat('c1',24));raise exception 'Aux dispensed quantified drug';exception when raise_exception then if sqlerrm<>'quantified_dispensing_professional_only' then raise;end if;end;
 begin perform public.inv_order_approve(current_setting('test.inv_draft')::uuid,repeat('c2',24));raise exception 'Aux approved order';exception when raise_exception then if sqlerrm<>'inventory_admin_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.inv_shift_open(:'clinic','0',repeat('c3',24)) as mvzshift \gset
select public.inv_dispensing_authorize(:'drug',:'rxitem','1',clock_timestamp()+interval '1 day','Cantidad de envases ficticia',repeat('c6',24));
select public.inv_sale_post(:'mvzshift','tarjeta',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'drug','lot_id',:'druglot','quantity','1','price','100.00','prescription_item_id',:'rxitem')),'100.00',repeat('c4',24));
select id as vial from public.medication_vials where lot='LOTE-SINTETICO' limit 1 \gset
select public.inv_vial_link(:'vial',:'druglot','1',repeat('c5',24));
select public.inv_vial_link(:'vial',:'druglot','1',repeat('c5',24));
do $$begin
 if (select cantidad from public.lotes_inventario where id=current_setting('test.inv_druglot')::uuid)<>2 then raise exception 'Vial link doubled or failed';end if;
 if (select count(*) from public.inventory_vial_links)<>1 then raise exception 'Vial duplicate';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select public.inv_product_save(:'clinic',null,0,'{"name":"Fármaco ordinario ficticio","presentation":"Frasco ficticio","kind":"farmaco","unit":"frasco","medication_version_id":"10000000-0000-0000-0000-000000000001","price":"10.00","cost":"2.00","minimum":"0","reorder":"1"}',repeat('c7',24)) as ordinary_item \gset
select public.inv_lot_receive(:'ordinary_item','ORDINARY-SYNTHETIC',current_date+90,'3','2.00',repeat('c8',24)) as ordinary_lot \gset
select set_config('test.inv_ordinary_item',:'ordinary_item',true);select set_config('test.inv_ordinary_lot',:'ordinary_lot',true);
select id as ordinary_rxitem,prescription_id as ordinary_rx from public.prescription_items where prescription_id in(select id from public.prescriptions where not controlled and state='issued') limit 1 \gset
select case_id as ordinary_case from public.prescriptions where id=:'ordinary_rx' \gset
select set_config('test.inv_ordinary_rxitem',:'ordinary_rxitem',true);
select public.inv_sale_post(:'shift2','transferencia','[{"kind":"servicio","name":"Servicio ficticio","quantity":"1","price":"20.00","cost":"3.00","commission":"2.00","professional_id":"00000000-0000-0000-0000-000000000062"}]','20.00',repeat('c9',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.inv_dispensing_authorize(:'ordinary_item',:'ordinary_rxitem','2',clock_timestamp()+interval '1 day','Envases ficticios',repeat('d3',24));
select id as mvz_profile from public.professional_profiles where user_id=auth.uid() and clinic_id=:'clinic' \gset
select public.rx_delegate(:'mvz_profile','00000000-0000-0000-0000-000000000063',:'ordinary_case','{"use_data":false,"use_signature":false,"prepare_ordinary":false,"issue_ordinary":false,"dispense_ordinary":true}',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('d4',24)) as dispensing_grant \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select public.inv_sale_post(:'auxshift','efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'ordinary_item','lot_id',:'ordinary_lot','quantity','1','price','10.00','prescription_item_id',:'ordinary_rxitem')),'10.00',repeat('d5',24));
do $$begin
 if exists(select 1 from public.inventory_sales where cashier_id<>auth.uid()) then raise exception 'Another cashier financial data leaked';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.rx_delegate_revoke(:'dispensing_grant','Revocación ficticia',repeat('d6',24));
do $$begin
 begin perform public.inv_sale_post((select id from public.inventory_cash_shifts where cashier_id=auth.uid() and closed_at is null),'tarjeta',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.inv_drug'),'lot_id',current_setting('test.inv_druglot'),'quantity','1','price','100.00','prescription_item_id',current_setting('test.inv_rxitem'))),'100.00',repeat('d7',24));raise exception 'Repeated Rx beyond authorized amount';exception when raise_exception then if sqlerrm<>'dispensing_authorized_quantity_exceeded' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
do $$begin
 begin perform public.inv_sale_post(current_setting('test.inv_auxshift')::uuid,'efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',current_setting('test.inv_ordinary_item'),'lot_id',current_setting('test.inv_ordinary_lot'),'quantity','1','price','10.00','prescription_item_id',current_setting('test.inv_ordinary_rxitem'))),'10.00',repeat('d8',24));raise exception 'Revoked auxiliary dispensed';exception when raise_exception then if sqlerrm<>'ordinary_dispensing_delegation_required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000064',true);
do $$begin
 if exists(select 1 from public.inventario) or exists(select 1 from public.inventory_sales) then raise exception 'Cross clinic sales/stock leak';end if;
 begin perform public.inv_dashboard(current_setting('test.inv_clinic')::uuid);raise exception 'Cross clinic RPC leak';exception when raise_exception then if sqlerrm<>'inventory_access_required' then raise;end if;end;
end $$;
reset role;
do $$begin
 begin update public.inventory_sales set total=0;raise exception 'Sale altered';exception when raise_exception then if sqlerrm<>'inventory_history_is_immutable' then raise;end if;end;
 begin update public.inventory_cash_shifts set snapshot='{}' where closed_at is not null;raise exception 'Frozen cut altered';exception when raise_exception then if sqlerrm<>'inventory_history_is_immutable' then raise;end if;end;
end $$;
commit;
