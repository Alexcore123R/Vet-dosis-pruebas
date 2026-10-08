#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
test_logs=$(mktemp -d)
trap 'rm -rf "$test_logs"' EXIT
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$test_logs/setup" <<'SQL'
begin;
insert into auth.users values('00000000-0000-0000-0000-000000000085','cash85@example.test',now());
select id as clinic from public.clinics where name='Módulos restantes ficticios' \gset
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000000085','recepcion');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000085',true);
select public.inv_shift_open(:'clinic','0',repeat('c1',24));
select public.ops_write(:'clinic','service_act',jsonb_build_object('service_id',(public.ops_dashboard(:'clinic')->'services'->0->>'id'),'professional_id','00000000-0000-0000-0000-000000000083'),repeat('c2',24));
commit;
SQL
for actor in 82 85; do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -v actor="$actor" > "$test_logs/$actor" 2>&1 <<'SQL' &
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000'||:'actor',true);
select clinic_id as clinic,id as shift from public.inventory_cash_shifts where cashier_id=auth.uid() and closed_at is null \gset
select public.ops_dashboard(:'clinic')->'acts' as acts \gset
select value->>'id' as act from jsonb_array_elements(:'acts'::jsonb) where value->>'paid'='false' \gset
select public.inv_sale_post(:'shift','efectivo',jsonb_build_array(jsonb_build_object('kind','servicio','service_act_id',:'act','quantity','1','price','300.00')),'300.00',repeat('c'||:'actor',16));
select pg_sleep(1);
commit;
SQL
 if [ "$actor" = 82 ];then first_pid=$!;else second_pid=$!;fi
done
first_status=0;second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
if [ "$first_status" = 0 ] && [ "$second_status" = 0 ];then cat "$test_logs/82" "$test_logs/85";exit 1;fi
if [ "$first_status" != 0 ] && [ "$second_status" != 0 ];then cat "$test_logs/82" "$test_logs/85";exit 1;fi
if ! rg -q 'service_already_paid' "$test_logs";then cat "$test_logs/82" "$test_logs/85";exit 1;fi
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$declare act uuid;begin
 select id into act from public.clinic_service_acts where name='Otro precio';
 if (select count(*) from public.inventory_sale_lines where service_act_id=act)<>1 then raise exception 'Concurrent duplicate service charge';end if;
 if (select commission from public.inventory_sale_lines where service_act_id=act)<>150 then raise exception 'Concurrent commission wrong';end if;
end$$;
SQL
printf 'M9 concurrent cashiers: one service charged once, frozen commission preserved.\n'
