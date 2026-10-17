-- Candidate only: apply after inventory M8. Does not modify records or grants.
-- Same authorized callers as existing inv_totals/inv_dashboard.
-- Count/average: whole sales within period, excluding reversals before period end.
-- Empty period has count 0 and average NULL (never divide net cash by a line count).
begin;
do $$begin
 if to_regprocedure('private.inv_totals(uuid,uuid,timestamptz,timestamptz)') is null then
  raise exception 'inventory_totals_dependency_required';
 end if;
end $$;
create or replace function private.inv_totals(clinic uuid,shift uuid,start_time timestamptz,end_time timestamptz) returns jsonb language sql stable security definer set search_path='' as $$
 with valid_sales as (
 select s.total from public.inventory_sales s
 where s.clinic_id=$1 and ($2 is null or s.shift_id=$2)
 and ($3 is null or s.created_at>=$3) and ($4 is null or s.created_at<$4)
 and not exists(select 1 from public.inventory_sale_reversals r
   where r.sale_id=s.id and ($4 is null or r.created_at<$4))),
 sale_metrics as (select count(*) sale_count,round(avg(total),2) average_ticket from valid_sales),
 flows as (
 select s.id,s.method,s.total,s.cost,s.commission from public.inventory_sales s where s.clinic_id=$1 and ($2 is null or s.shift_id=$2) and ($3 is null or s.created_at>=$3) and ($4 is null or s.created_at<$4)
 union all select s.id,s.method,-s.total,-s.cost,-s.commission from public.inventory_sale_reversals r join public.inventory_sales s on s.id=r.sale_id where r.clinic_id=$1 and ($2 is null or r.shift_id=$2) and ($3 is null or r.created_at>=$3) and ($4 is null or r.created_at<$4)),
 money as (select coalesce(sum(total),0) gross,coalesce(sum(cost),0) cost,coalesce(sum(commission),0) commission,coalesce(sum(total) filter(where method='efectivo'),0) cash,coalesce(sum(total) filter(where method='tarjeta'),0) card,coalesce(sum(total) filter(where method='transferencia'),0) transfer from flows),
 cashmoves as (select coalesce(sum(amount) filter(where kind='ingreso'),0) income,coalesce(sum(amount) filter(where kind='retiro'),0) withdrawal,coalesce(sum(amount) filter(where kind='gasto'),0) expense from public.inventory_cash_movements m where m.clinic_id=$1 and ($2 is null or m.shift_id=$2) and ($3 is null or m.created_at>=$3) and ($4 is null or m.created_at<$4))
 select jsonb_build_object('sale_count',sale_count,'average_ticket',average_ticket::text,'gross',gross::text,'cost',cost::text,'commission',commission::text,'margin',(gross-cost-commission)::text,'recorded_net',(gross-cost-commission-expense)::text,'cash',cash::text,'card',card::text,'transfer',transfer::text,'income',income::text,'withdrawal',withdrawal::text,'expense',expense::text) from money,cashmoves,sale_metrics;
$$;
commit;
