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
 echo 'Dispensing concurrency coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','controlled.dispense',null,clock_timestamp()+interval '1 day','Synthetic dispensing concurrency');
reset role;
select id as item from public.inventario where nombre='Synthetic dispensing ordinary' \gset
select x.id as rxitem from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.instructions='Synthetic standing' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_dispensing_authorize(:'item',:'rxitem','3',clock_timestamp()+interval '1 hour','Synthetic three total units',repeat('1431',12));
SQL
cat > "$work_dir/deliver.sql" <<'SQL'
select id as lot from public.lotes_inventario where lote='SYNTHETIC-DISPENSING' \gset
select x.id as rxitem from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.instructions='Synthetic standing' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_delivery_prepare(:'lot',:'rxitem','1',repeat('1432',12));
SQL
{ echo 'begin;';cat "$work_dir/deliver.sql";echo 'select pg_advisory_xact_lock(771201);select pg_sleep(2);commit;'; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771201
cat > "$work_dir/second.sql" <<'SQL'
select id as lot,item_id as item from public.lotes_inventario where lote='SYNTHETIC-DISPENSING' \gset
select x.id as rxitem from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.instructions='Synthetic standing' \gset
select id as shift from public.inventory_cash_shifts where cashier_id='00000000-0000-0000-0000-000000000151' and closed_at is null \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'item','lot_id',:'lot','quantity','1','price','10','prescription_item_id',:'rxitem')),'10',repeat('1433',12));
SQL
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/second.sql" > "$work_dir/second.log" 2>&1;then echo 'Concurrent deliveries exceeded total quantity';exit 1;fi
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
grep -Fq dispensing_authorized_quantity_exceeded "$work_dir/second.log" || { cat "$work_dir/second.log";exit 1; }
# Revoke first, then retry an old successful receipt: re-check current authority.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select permission_grant_id as grant_id from public.inventory_dispensing_limits order by created_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic concurrent revoke');
select pg_advisory_xact_lock(771202);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771202
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/deliver.sql" > "$work_dir/retry.log" 2>&1;then echo 'Revoked dispenser replayed receipt';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq verified_dispensing_permission_required "$work_dir/retry.log" || { cat "$work_dir/retry.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select cantidad from public.lotes_inventario where lote='SYNTHETIC-DISPENSING')<>7 then raise exception 'concurrent_stock_mismatch';end if;
 if (select count(*) from public.inventory_delivery_tickets dt join public.inventario i on i.id=dt.item_id where i.nombre='Synthetic dispensing ordinary')<>2 then raise exception 'duplicate_or_missing_delivery';end if;
end$$;
SQL
echo 'Dispensing concurrency passed: one remaining unit, revocation blocks old receipt.'
# A dispensing grant may expire while the statement waits for the clinic lock.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as item from public.inventario where nombre='Synthetic dispensing ordinary' \gset
select x.id as rxitem from public.prescription_items x join public.prescriptions r on r.id=x.prescription_id where r.instructions='Synthetic standing' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','controlled.dispense',null,clock_timestamp()+interval '8 seconds','Synthetic expiry during wait');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.inv_dispensing_authorize(:'item',:'rxitem','5',clock_timestamp()+interval '1 hour','Synthetic expiry test',repeat('1434',12));
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771203);select pg_sleep(10);commit;
SQL
first_pid=$!
wait_marker 771203
sed "s/'1432'/'1435'/" "$work_dir/deliver.sql" > "$work_dir/expiry-deliver.sql"
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/expiry-deliver.sql" > "$work_dir/expiry.log" 2>&1;then echo 'Expired dispensing grant accepted after wait';exit 1;fi
wait "$first_pid" || { cat "$work_dir/expiry-lock.log";exit 1; }
grep -Fq verified_dispensing_permission_required "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select cantidad from public.lotes_inventario where lote='SYNTHETIC-DISPENSING')<>7 then raise exception 'expired_permission_changed_stock';end if;
end$$;
SQL
echo 'Dispensing expiry after lock wait passed: no stock movement.'
