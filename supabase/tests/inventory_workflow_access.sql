begin;
insert into auth.users values('00000000-0000-0000-0000-000000000066','reception@example.test',now());
insert into public.clinic_members(clinic_id,user_id,role) select clinic_id,'00000000-0000-0000-0000-000000000066','recepcion' from public.inventario where nombre='Producto sintético';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select clinic_id as clinic from public.inventario where nombre='Producto sintético' \gset
select public.inv_application_tariff(:'clinic','10000000-0000-0000-0000-000000000001','15.00',repeat('e1',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.inv_delivery_grant(:'clinic','00000000-0000-0000-0000-000000000066',null,'Entrega ordinaria delegada',repeat('e2',24)) as grant \gset
select id as rx,case_id as case from public.prescriptions where state='issued' and not controlled limit 1 \gset
select id as rxitem from public.prescription_items where prescription_id=:'rx' \gset
select id as item from public.inventario where nombre='Fármaco ordinario ficticio' \gset
select id as lot from public.lotes_inventario where item_id=:'item' \gset
-- Add physical stock; one envase is opened once, two separate applications share one recipe.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select public.inv_lot_receive(:'item','ORDINARY-APPLICATION',current_date+90,'1','2.00',repeat('e3',24)) as applicationlot \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select public.rx_vial_open(:'clinic','10000000-0000-0000-0000-000000000001','ORDINARY-APPLICATION','10',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),null,null,repeat('e4',24)) as vial \gset
select public.inv_vial_link(:'vial',:'applicationlot','1',repeat('e5',24));
select public.rx_medication_report(:'case',jsonb_build_object('product_version_id','10000000-0000-0000-0000-000000000001','quantity','0.5','unit','ml','route','Vía ficticia','procedure','cuidados','performed_by',auth.uid(),'prescription_id',:'rx','vial_id',:'vial','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('e6',24)) as first_record \gset
select public.rx_medication_report(:'case',jsonb_build_object('product_version_id','10000000-0000-0000-0000-000000000001','quantity','0.5','unit','ml','route','Vía ficticia','procedure','cuidados','performed_by',auth.uid(),'prescription_id',:'rx','vial_id',:'vial','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('e7',24)) as second_record \gset
select public.inv_application_prepare(:'first_record',repeat('e8',24)) as first_charge \gset
select public.inv_application_prepare(:'second_record',repeat('e9',24)) as second_charge \gset
select set_config('test.workflow_vial',:'vial',true);select set_config('test.workflow_lot',:'applicationlot',true);
select set_config('test.workflow_charge',:'first_charge',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000066',true);
select public.inv_shift_open(:'clinic','0',repeat('f1',24)) as shift \gset
select public.inv_delivery_prepare(:'lot',:'rxitem','1',repeat('f2',24)) as delivery \gset
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','charge_id',:'first_charge','quantity','1','price','15.00')),'15.00',repeat('f3',24));
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','charge_id',:'second_charge','quantity','1','price','15.00')),'15.00',repeat('f4',24));
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','delivery_id',:'delivery','quantity','1','price','10.00')),'10.00',repeat('f5',24));
select set_config('test.workflow_shift',:'shift',true);
do $$begin
 if (select cantidad from public.lotes_inventario where id=current_setting('test.workflow_lot')::uuid)<>0 then raise exception 'Billing sold another bottle';end if;
 if (public.inv_shift_snapshot(current_setting('test.workflow_shift')::uuid)->'totals'->>'gross')::numeric<>40 then raise exception 'Repeated recipe charges lost';end if;
 if exists(select 1 from public.controlled_drug_reviews where validated_by=auth.uid()) then raise exception 'Cash collection became clinical validation';end if;
 begin perform public.inv_sale_post(current_setting('test.workflow_shift')::uuid,'efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','charge_id',current_setting('test.workflow_charge'),'quantity','1','price','15.00')),'15.00',repeat('f6',24));raise exception 'One application billed twice';exception when raise_exception then if sqlerrm<>'application_already_paid' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select id as controlled_item from public.inventario where nombre='Fármaco sintético controlado' \gset
select id as controlled_lot from public.lotes_inventario where item_id=:'controlled_item' \gset
select id as controlled_rxitem from public.prescription_items where prescription_id in(select id from public.prescriptions where controlled and state='issued') limit 1 \gset
select public.inv_dispensing_authorize(:'controlled_item',:'controlled_rxitem','2',clock_timestamp()+interval '1 day','Envases ficticios',repeat('f7',24));
select public.inv_delivery_prepare(:'controlled_lot',:'controlled_rxitem','1',repeat('f8',24)) as controlled_delivery \gset
select public.inv_delivery_revoke(:'grant','Revocado por responsable',repeat('f9',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000066',true);
select public.inv_sale_post(:'shift','tarjeta',jsonb_build_array(jsonb_build_object('kind','servicio','delivery_id',:'controlled_delivery','quantity','1','price','100.00')),'100.00',repeat('a9',24));
do $$begin
 if jsonb_array_length(public.inv_delivery_items((select clinic_id from public.inventory_cash_shifts where id=current_setting('test.workflow_shift')::uuid)))<>0 then raise exception 'Revoked reception retains delivery access';end if;
end $$;
reset role;
do $$begin
 if private.rx_vial_balance(current_setting('test.workflow_vial')::uuid)<>9 then raise exception 'Payment rededucted volume';end if;
end $$;
rollback;
