-- Payment references: observational ledger, never charges cards or duplicates POS money.
-- Apply once after M9-M11. API providers remain unconfigured.
begin;
create table public.payment_transactions(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),sale_id uuid,
 direction text not null check(direction in ('ingreso','egreso')),method text not null check(method in ('efectivo','transferencia','tarjeta')),
 amount numeric(18,2) not null check(amount>0),currency text not null default 'MXN' check(currency='MXN'),
 provider text not null check(length(btrim(provider)) between 1 and 120),external_reference text,
 occurred_at timestamptz not null,card_last_four text check(card_last_four~'^[0-9]{4}$'),
 notes text not null default '' check(length(notes)<=1000),reported_by uuid not null references auth.users(id),reported_at timestamptz not null default clock_timestamp(),
 unique(clinic_id,id),foreign key(clinic_id,sale_id) references public.inventory_sales(clinic_id,id),
 check(sale_id is null or direction='ingreso'),check(method='efectivo' or length(btrim(external_reference)) between 1 and 200),
 check(card_last_four is null or method='tarjeta'));
create unique index payment_external_unique on public.payment_transactions(clinic_id,provider,external_reference) where external_reference is not null;
create table public.payment_reconciliations(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,transaction_id uuid not null,decision text not null check(decision in ('verificada','rechazada')),
 fee numeric(18,2) not null check(fee>=0),reason text not null check(length(btrim(reason)) between 5 and 1000),reviewed_by uuid not null references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
 foreign key(clinic_id,transaction_id) references public.payment_transactions(clinic_id,id));
create trigger payment_transaction_immutable before update or delete on public.payment_transactions for each row execute function private.inv_history_guard();
create trigger payment_review_immutable before update or delete on public.payment_reconciliations for each row execute function private.inv_history_guard();
alter table public.payment_transactions enable row level security;alter table public.payment_reconciliations enable row level security;
revoke all on public.payment_transactions,public.payment_reconciliations from public,anon,authenticated;
create function public.pay_dashboard(p_clinic uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.inv_access(p_clinic) then raise exception 'access_denied';end if;
 return jsonb_build_object(
 'sales',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'method',s.method,'total',s.total::text,'created_at',s.created_at,'cashier_id',s.cashier_id,'reversed',exists(select 1 from public.inventory_sale_reversals rv where rv.sale_id=s.id)) order by s.created_at desc),'[]') from public.inventory_sales s where clinic_id=p_clinic and (cashier_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))),
 'transactions',(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('amount',t.amount::text,'state',coalesce(r.decision,'pendiente_revision'),'fee',r.fee::text,'net',case when r.decision='verificada' then (t.amount-r.fee)::text end,'review_reason',r.reason) order by t.reported_at desc),'[]') from public.payment_transactions t left join lateral (select * from public.payment_reconciliations r where r.transaction_id=t.id order by reviewed_at desc,id desc limit 1) r on true where t.clinic_id=p_clinic and (t.reported_by=auth.uid() or private.has_clinic_role(p_clinic,array['admin']))));
end$$;
create function public.pay_report(p_clinic uuid,p_data jsonb,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare fp jsonb;v_id uuid;s public.inventory_sales;amount numeric;ref text;
begin
 if not private.inv_access(p_clinic) then raise exception 'access_denied';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'invalid_data';end if;
 -- Reject unexpected fields rather than storing raw provider/card payloads.
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in ('sale_id','direction','method','amount','provider','external_reference','occurred_at','card_last_four','notes')) then raise exception 'unsupported_payment_fields';end if;
 fp=jsonb_build_object('kind','payment_reference','data',p_data);v_id=private.vet_receipt(p_clinic,p_operation,fp);if v_id is not null then return v_id;end if;
 amount=private.inv_money(p_data->>'amount');ref=nullif(btrim(p_data->>'external_reference'),'');
 if nullif(p_data->>'sale_id','') is not null then
 select * into s from public.inventory_sales where id=(p_data->>'sale_id')::uuid and clinic_id=p_clinic for share;
 if not found or not (s.cashier_id=auth.uid() or private.has_clinic_role(p_clinic,array['admin'])) then raise exception 'own_sale_required';end if;
 if exists(select 1 from public.inventory_sale_reversals where sale_id=s.id) then raise exception 'reversed_sale';end if;
 if amount>s.total or p_data->>'method'<>s.method then raise exception 'payment_sale_mismatch';end if;
 end if;
 insert into public.payment_transactions(clinic_id,sale_id,direction,method,amount,provider,external_reference,occurred_at,card_last_four,notes,reported_by)
 values(p_clinic,s.id,p_data->>'direction',p_data->>'method',amount,lower(btrim(p_data->>'provider')),ref,(p_data->>'occurred_at')::timestamptz,nullif(p_data->>'card_last_four',''),coalesce(p_data->>'notes',''),auth.uid()) returning id into v_id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,v_id);
 insert into public.audit_log(clinic_id,actor_id,action,entity_id) values(p_clinic,auth.uid(),'payment_reported',v_id::text);
 return v_id;
end$$;
create function public.pay_reconcile(p_id uuid,p_decision text,p_fee text,p_reason text,p_operation text) returns uuid language plpgsql security definer set search_path='' as $$
declare t public.payment_transactions;v_id uuid;fp jsonb;fee numeric;allocated numeric;total numeric;
begin
 select * into t from public.payment_transactions where id=p_id for update;
 if not found or not private.has_clinic_role(t.clinic_id,array['admin']) then raise exception 'admin_required';end if;
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
-- Add the observational ledger to the existing export without rebuilding its snapshot.
alter function private.clinic_snapshot(uuid) rename to clinic_snapshot_before_payments;
create function private.clinic_snapshot(p_clinic uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare snapshot jsonb;
begin
 snapshot=private.clinic_snapshot_before_payments(p_clinic)::jsonb;
 snapshot=jsonb_set(snapshot,'{tables,payment_transactions}',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from public.payment_transactions t where clinic_id=p_clinic));
 snapshot=jsonb_set(snapshot,'{tables,payment_reconciliations}',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from public.payment_reconciliations t where clinic_id=p_clinic));
 return snapshot::text;
end$$;
revoke all on function private.clinic_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.pay_dashboard(uuid),public.pay_report(uuid,jsonb,text),public.pay_reconcile(uuid,text,text,text,text) from public,anon;
grant execute on function public.pay_dashboard(uuid),public.pay_report(uuid,jsonb,text),public.pay_reconcile(uuid,text,text,text,text) to authenticated;
commit;
