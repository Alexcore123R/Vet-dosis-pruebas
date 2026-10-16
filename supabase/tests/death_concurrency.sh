#!/usr/bin/env bash
set -euo pipefail
container_name=$1
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as procedure from private.procedure_types where clinic_id=:'clinic' and name='Synthetic death ascertainment' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','clinical.death.record',:'procedure',clock_timestamp()+interval '1 day','Synthetic simultaneous ascertainment');reset role;
create table private.synthetic_death_input as select d.id as consent,jsonb_build_object('procedure_id',:'procedure','result','no_confirmada','method','Synthetic method','findings','Synthetic concurrent findings','observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'signer_name','Synthetic observer','signature','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]'::jsonb,'confirmed',true) as data from public.form_documents d where snapshot='{"schema":{"type":"euthanasia"}}'::jsonb;
SQL
for attempt in 1 2;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/write-$attempt.log" 2>&1 <<'SQL' &
select consent,data from private.synthetic_death_input \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.clinical_death_add(:'consent',:'data'::jsonb,repeat('2221',12));
SQL
 eval "pid_$attempt=$!"
done
for attempt in 1 2;do eval "pid=\$pid_$attempt";wait "$pid" || { cat "$work_dir/write-$attempt.log";exit 1; };done
count=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from public.clinical_death_records where findings='Synthetic concurrent findings'")
[ "$count" = 1 ] || { echo 'Concurrent ascertainment duplicated';exit 1; }
echo 'Concurrent ascertainment idempotence passed.'

docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as procedure from private.procedure_types where clinic_id=:'clinic' and name='Synthetic death ascertainment' \gset
select private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000151','clinical.death.record',:'procedure') as grant_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic expiry');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','clinical.death.record',:'procedure',clock_timestamp()+interval '8 seconds','Synthetic short permission');reset role;
update private.synthetic_death_input set data=data||jsonb_build_object('observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771519);select pg_sleep(10);commit;
SQL
locker=$!
ready=false
for attempt in {1..100};do
 if [ "$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from pg_locks where locktype='advisory' and objid=771519 and granted")" = 1 ];then ready=true;break;fi
 sleep .1
done
[ "$ready" = true ] || { echo 'Lock marker unavailable';exit 1; }
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expired.log" 2>&1 <<'SQL'
select consent,data from private.synthetic_death_input \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.clinical_death_add(:'consent',:'data'::jsonb,repeat('2222',12));
SQL
then echo 'Expired authority accepted';exit 1;fi
wait "$locker"
grep -Fq explicit_permission_required "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
echo 'Expiry after lock wait passed.'
