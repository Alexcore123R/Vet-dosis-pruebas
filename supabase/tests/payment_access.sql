\set ON_ERROR_STOP on
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select clinic_id as clinic from public.clinic_members where user_id=auth.uid() \gset
select (public.pay_dashboard(:'clinic')->'sales'->0->>'id') as sale \gset
select set_config('test.pay_clinic',:'clinic',true);select set_config('test.pay_sale',:'sale',true);
select public.pay_report(:'clinic',jsonb_build_object('sale_id',:'sale','direction','ingreso','method','efectivo','amount','100.00','provider','Caja ficticia','external_reference','TEST-REFERENCE-1','occurred_at',now()),repeat('d3',24)) as txn \gset
select set_config('test.pay_txn',:'txn',true);
-- Retry: same data and operation returns same transaction; amounts do not touch POS.
select public.pay_report(:'clinic',jsonb_build_object('sale_id',:'sale','direction','ingreso','method','efectivo','amount','100.00','provider','Caja ficticia','external_reference','TEST-REFERENCE-1','occurred_at',now()),repeat('d3',24));
do $$begin
 if (public.pay_dashboard(current_setting('test.pay_clinic')::uuid)->'transactions'->0->>'state')<>'pendiente_revision' then raise exception 'reference automatically confirms payment';end if;
 begin perform public.pay_reconcile(current_setting('test.pay_txn')::uuid,'verificada','0','Conciliación ficticia',repeat('d4',24));raise exception 'reception validated payment';exception when others then if sqlerrm<>'admin_required' then raise;end if;end;
 begin perform public.pay_report(current_setting('test.pay_clinic')::uuid,jsonb_build_object('direction','ingreso','method','tarjeta','amount','10','provider','Ficticio','external_reference','CARD-TEST','occurred_at',now(),'card_number','1234'),repeat('d5',24));raise exception 'raw card data accepted';exception when others then if sqlerrm<>'unsupported_payment_fields' then raise;end if;end;
 begin perform public.pay_report(current_setting('test.pay_clinic')::uuid,jsonb_build_object('direction','ingreso','method','efectivo','amount','10','provider','Caja ficticia','external_reference','TEST-REFERENCE-1','occurred_at',now()),repeat('d6',24));raise exception 'duplicate reference';exception when unique_violation then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.pay_reconcile(:'txn','verificada','2.50','Conciliación manual ficticia',repeat('d7',24));
select public.pay_report(:'clinic',jsonb_build_object('sale_id',:'sale','direction','ingreso','method','efectivo','amount','150.00','provider','Caja ficticia','external_reference','TEST-REFERENCE-2','occurred_at',now()),repeat('d8',24)) as second \gset
select set_config('test.pay_second',:'second',true);
do $$begin
 if (public.pay_dashboard(current_setting('test.pay_clinic')::uuid)->'transactions'->1->>'net')::numeric<>97.50 then raise exception 'payment net mismatch';end if;
 begin perform public.pay_reconcile(current_setting('test.pay_second')::uuid,'verificada','0','Revisión ficticia',repeat('d9',24));raise exception 'overallocated receipt';exception when others then if sqlerrm<>'payment_allocation_exceeds_sale' then raise;end if;end;
 if (select count(*) from public.inventory_sales where clinic_id=current_setting('test.pay_clinic')::uuid)<>1 then raise exception 'payment reference duplicated sale';end if;
 if not (public.clinic_export(current_setting('test.pay_clinic')::uuid)::jsonb->'tables' ? 'payment_transactions') then raise exception 'payments absent in backup';end if;
end$$;
select public.pay_report(:'clinic',jsonb_build_object('direction','egreso','method','transferencia','amount','50.25','provider','Banco elegido por clínica','external_reference','TEST-EXPENSE-1','occurred_at',now()),repeat('da',24));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000084',true);
do $$begin
 begin perform public.pay_dashboard(current_setting('test.pay_clinic')::uuid);raise exception 'outside payment read';exception when others then if sqlerrm<>'access_denied' then raise;end if;end;
end$$;
rollback;
