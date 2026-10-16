#!/usr/bin/env bash
set -euo pipefail
container_name=$1
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
for attempt in 1 2;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/register-$attempt.log" 2>&1 <<'SQL' &
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.clinical_case_register(:'clinic',jsonb_build_object('patient_id',:'patient','responsible_id','00000000-0000-0000-0000-000000000151','kind','clinical_history','clinical_date',current_date,'reason','Synthetic simultaneous context'),repeat('2121',12));
SQL
 eval "pid_$attempt=$!"
done
for attempt in 1 2;do eval "pid=\$pid_$attempt";wait "$pid" || { cat "$work_dir/register-$attempt.log";exit 1; };done
count=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from public.clinical_cases where reason='Synthetic simultaneous context'")
[ "$count" = 1 ] || { echo 'Concurrent intake duplicated context';exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000170','clinical.case.prepare') as grant_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic expiry test');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','clinical.case.prepare',null,clock_timestamp()+interval '8 seconds','Synthetic short intake permission');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771518);select pg_sleep(10);commit;
SQL
locker=$!
ready=false
for attempt in {1..100};do
 if [ "$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from pg_locks where locktype='advisory' and objid=771518 and granted")" = 1 ];then ready=true;break;fi
 sleep .1
done
[ "$ready" = true ] || { echo 'Lock marker unavailable';exit 1; }
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expired.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.clinical_case_register(:'clinic',jsonb_build_object('patient_id',:'patient','responsible_id','00000000-0000-0000-0000-000000000151','kind','clinical_history','clinical_date',current_date,'reason','Synthetic expired context'),repeat('2122',12));
SQL
then echo 'Expired preparer registered case';exit 1;fi
wait "$locker" || { cat "$work_dir/lock.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
count=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from public.clinical_cases where reason='Synthetic expired context'")
[ "$count" = 0 ] || { echo 'Expired context persisted';exit 1; }
echo 'Concurrent intake idempotence and expiry after lock wait passed.'
