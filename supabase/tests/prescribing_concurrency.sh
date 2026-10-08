#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
test_logs=$(mktemp -d)
trap 'rm -rf "$test_logs"' EXIT
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$test_logs/setup" <<'SQL'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select clinic_id as clinic from public.clinical_cases limit 1 \gset
select public.rx_vial_open(:'clinic','10000000-0000-0000-0000-000000000002','CONCURRENCY-SYNTHETIC','2',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),null,null,repeat('c1',24));
select id as vial from public.medication_vials where lot='CONCURRENCY-SYNTHETIC' \gset
select public.rx_vial_adjust(:'vial','merma','-0.1','Merma ficticia',repeat('c2',24));
select public.rx_vial_adjust(:'vial','merma','-0.1','Merma ficticia',repeat('c2',24));
select public.rx_vial_adjust(:'vial','devolucion','0.1','Devolución ficticia',repeat('c3',24));
commit;
SQL
for actor in a b; do
  docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -v actor="$actor" > "$test_logs/$actor" 2>&1 <<'SQL' &
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select id as case_id from public.clinical_cases limit 1 \gset
select id as vial from public.medication_vials where lot='CONCURRENCY-SYNTHETIC' \gset
select public.rx_medication_report(:'case_id',jsonb_build_object('product_version_id','10000000-0000-0000-0000-000000000002','quantity','1.5','unit','ml','route','Ficticia','procedure','cuidados','performed_by','00000000-0000-0000-0000-000000000062','vial_id',:'vial','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat(:'actor'||'c',24));
select pg_sleep(1);
commit;
SQL
  if [ "$actor" = a ]; then actor_a_pid=$!; else actor_b_pid=$!; fi
done
wait "$actor_a_pid"
wait "$actor_b_pid"
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$declare v uuid;begin
 select id into v from public.medication_vials where lot='CONCURRENCY-SYNTHETIC';
 if private.rx_vial_balance(v)<>-1 then raise exception 'Concurrent volume lost or adjustment retried twice';end if;
 if (select count(*) from public.medication_records where vial_id=v)<>2 then raise exception 'Concurrent application lost';end if;
 if (select count(*) from public.medication_records where vial_id=v and incidence<>'')<>1 then raise exception 'Insufficient balance not preserved as incidence';end if;
 if (select count(*) from public.medication_vial_movements where vial_id=v)<>4 then raise exception 'Movement duplicated or lost';end if;
end $$;
SQL
printf 'M6 concurrent applications and exact adjustment retries passed.\n'
