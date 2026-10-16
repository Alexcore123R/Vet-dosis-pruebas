#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
wait_marker(){
 for attempt in {1..40};do
  if [ "$(docker exec "$container_name" psql -U postgres -Atc "select pg_try_advisory_lock($1)")" = f ];then return;fi
  sleep 0.1
 done
 echo 'Inventory/cash coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_shift_open(:'clinic','0',repeat('1531',12));
SQL
cat > "$work_dir/sale.sql" <<'SQL'
select id as item from public.inventario where nombre='Synthetic explicit product' \gset
select id as lot from public.lotes_inventario where item_id=:'item' \gset
select id as shift from public.inventory_cash_shifts where cashier_id='00000000-0000-0000-0000-000000000170' and closed_at is null \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'item','lot_id',:'lot','quantity','1','price','10')),'10',repeat('1532',12));
SQL
{ echo 'begin;';cat "$work_dir/sale.sql";echo 'select pg_advisory_xact_lock(771211);select pg_sleep(2);commit;'; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771211
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sale.sql" > "$work_dir/second.log" 2>&1 || { cat "$work_dir/second.log";exit 1; }
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
# Current authority is checked before receipt replay, serialized with revocation.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000170' and code='sales.collect' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic concurrent collection revoke');
select pg_advisory_xact_lock(771212);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771212
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sale.sql" > "$work_dir/retry.log" 2>&1;then echo 'Revoked cashier replayed receipt';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/retry.log" || { cat "$work_dir/retry.log";exit 1; }
# Receiving expires while waiting: no statement-time permission reuse.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000170' and code='inventory.receive' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic receiving renewal');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','inventory.receive',null,clock_timestamp()+interval '8 seconds','Synthetic short receiving');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771213);select pg_sleep(10);commit;
SQL
first_pid=$!
wait_marker 771213
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL'
select id as item from public.inventario where nombre='Synthetic explicit product' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.inv_lot_receive(:'item','SYNTHETIC-EXPIRED-RECEIVING',current_date+90,'1','2',repeat('1533',12));
SQL
then echo 'Expired receiving grant moved stock';exit 1;fi
wait "$first_pid" || { cat "$work_dir/expiry-lock.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select stock from public.inventario where nombre='Synthetic explicit product')<>2 then raise exception 'duplicated_cash_or_expired_receiving_changed_stock';end if;
 if exists(select 1 from public.lotes_inventario where lote='SYNTHETIC-EXPIRED-RECEIVING') then raise exception 'expired_receiving_inserted_lot';end if;
 if (select count(*) from public.inventory_sales s join public.inventory_sale_lines l on l.sale_id=s.id join public.inventario i on i.id=l.item_id where i.nombre='Synthetic explicit product')<>2 then raise exception 'sale_retry_was_not_exactly_once';end if;
end$$;
SQL
echo 'Inventory/cash concurrency passed: one sale, live revocation and expiry after lock wait.'
