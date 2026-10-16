#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Two actual confirmations serialize on the ledger and emit one audit event.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_report_create(:'clinic','2020-03-01T00:00:00Z','2020-04-01T00:00:00Z',false,repeat('1621',12))->>'id' as report \gset
reset role;
select content_hash from public.controlled_drug_reports where id=:'report' \gset
set role service_role;
select public.rx_pdf_register('report',:'report',1,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-RACE','UTF8'),'base64'),encode(decode('89504e470d0a1a0a','hex'),'base64'));
SQL
cat > "$work_dir/confirm.sql" <<'SQL'
select id as report,pdf_hash from public.controlled_drug_reports where starts_at='2020-03-01T00:00:00Z' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_report_finalize(:'report',:'pdf_hash');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/a.log" 2>&1 &
first=$!
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/b.log" 2>&1 &
second=$!
wait "$first" || { cat "$work_dir/a.log";exit 1; }
wait "$second" || { cat "$work_dir/b.log";exit 1; }
result=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from public.audit_log where action='controlled_report_signed' and entity_id=(select id::text from public.controlled_drug_reports where starts_at='2020-03-01T00:00:00Z')")
[ "$result" = 1 ] || { echo 'Duplicate report emission';exit 1; }
echo 'Report concurrent confirmation passed.'
wait_marker(){
 for attempt in {1..40};do
  if [ "$(docker exec "$container_name" psql -U postgres -Atc "select pg_try_advisory_lock($1)")" = f ];then return;fi
  sleep 0.1
 done
 echo 'Report coordination failed';exit 1
}
# A role cannot replay issuance while revocation is committing.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000151' and code='report.issue' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic concurrent issue revocation');
select pg_advisory_xact_lock(771311);select pg_sleep(2);commit;
SQL
first=$!
wait_marker 771311
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/replay.log" 2>&1;then echo 'Revoked issuer replayed confirmation';exit 1;fi
wait "$first" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/replay.log" || { cat "$work_dir/replay.log";exit 1; }
# Real-time expiry after waiting on the clinic lock must also deny replay.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','report.issue',null,clock_timestamp()+interval '8 seconds','Synthetic short issue grant');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771312);select pg_sleep(10);commit;
SQL
first=$!
wait_marker 771312
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/expiry.log" 2>&1;then echo 'Expired issuer replayed confirmation';exit 1;fi
wait "$first" || { cat "$work_dir/lock.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
echo 'Report live revocation and expiry after lock wait passed.'
