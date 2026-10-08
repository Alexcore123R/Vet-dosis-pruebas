#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
test_logs=$(mktemp -d)
trap 'rm -rf "$test_logs"' EXIT
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$test_logs/setup" <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select clinic_id as clinic from public.clinic_members where user_id=auth.uid() limit 1 \gset
select public.inv_product_save(:'clinic',null,0,'{"name":"Concurrente ficticio","presentation":"Última unidad","kind":"producto","unit":"unidad","price":"0.10","cost":"0.05","minimum":"0","reorder":"1"}',repeat('d1',24)) as item \gset
select public.inv_lot_receive(:'item','CONCURRENCY-LAST',current_date+90,'1','0.05',repeat('d2',24));
commit;
SQL
for actor in 61 62; do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -v actor="$actor" > "$test_logs/$actor" 2>&1 <<'SQL' &
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000'||:'actor',true);
select id as shift from public.inventory_cash_shifts where cashier_id=auth.uid() and closed_at is null \gset
select id as item from public.inventario where nombre='Concurrente ficticio' \gset
select id as lot from public.lotes_inventario where item_id=:'item' \gset
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','producto','item_id',:'item','lot_id',:'lot','quantity','1','price','0.10')),'0.10',repeat(:'actor',24));
select pg_sleep(1);
commit;
SQL
 if [ "$actor" = 61 ]; then first_pid=$!;else second_pid=$!;fi
done
first_status=0;second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
if [ "$first_status" = 0 ] && [ "$second_status" = 0 ];then cat "$test_logs/61" "$test_logs/62";exit 1;fi
if [ "$first_status" != 0 ] && [ "$second_status" != 0 ];then cat "$test_logs/61" "$test_logs/62";exit 1;fi
if ! rg -q 'insufficient_stock' "$test_logs";then cat "$test_logs/61" "$test_logs/62";exit 1;fi
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$declare i uuid;begin
 select id into i from public.inventario where nombre='Concurrente ficticio';
 if (select stock from public.inventario where id=i)<>0 then raise exception 'Concurrent balance corrupted';end if;
 if (select count(*) from public.inventory_sale_lines where item_id=i)<>1 then raise exception 'Last item sold twice';end if;
 if (select sum(delta) from public.inventory_stock_movements where item_id=i)<>0 then raise exception 'Stock ledger mismatch';end if;
 if (select total from public.inventory_sale_lines where item_id=i)<>0.10 then raise exception 'Exact decimal price corrupted';end if;
end $$;
SQL
printf 'M8 concurrent cashiers: last unit sold once, exact totals preserved.\n'
