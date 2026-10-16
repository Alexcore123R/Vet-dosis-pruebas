#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Synthetic grant for the account created by permission_agenda.sql.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000090',m.clinic_id,m.user_id,m.created_at,'appointment.manage','00000000-0000-0000-0000-000000000080',clock_timestamp()+interval '1 day','Synthetic concurrency'
from public.clinic_members m join public.clinics c on c.id=m.clinic_id
where c.name='Synthetic agenda A' and m.user_id='00000000-0000-0000-0000-000000000081';
SQL
# Start revocation first and hold its transaction. Registration must wait and then deny.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000080',true);
set local role authenticated;
select public.permission_revoke('00000000-0000-0000-0000-000000000090','Synthetic concurrent revocation');
select pg_advisory_xact_lock(771135);
select pg_sleep(2);
commit;
SQL
publisher_pid=$!
ready=false
for attempt in {1..30};do
 available=$(docker exec "$container_name" psql -U postgres -Atc 'select pg_try_advisory_lock(771135)')
 if [ "$available" = f ];then ready=true;break;fi
 sleep 0.1
done
if [ "$ready" != true ];then wait "$publisher_pid";echo 'Revocation coordination failed';exit 1;fi
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/stale.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic agenda A' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',false);
set role authenticated;
select public.ops_write(:'clinic','appointment','{"patient_name":"Synthetic blocked after revoke","species":"synthetic","kind":"consulta","professional_id":"00000000-0000-0000-0000-000000000082","starts_at":"2040-01-01T12:00:00Z","ends_at":"2040-01-01T13:00:00Z"}',repeat('f',48));
SQL
then echo 'ERROR: revoked grant authorized waiting booking';exit 1;fi
wait "$publisher_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq 'explicit_permission_required' "$work_dir/stale.log" || { cat "$work_dir/stale.log";exit 1; }
# Expiration while blocked must also deny, even though statement time predates expiry.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL' &
begin;
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000091',m.clinic_id,m.user_id,m.created_at,'appointment.manage','00000000-0000-0000-0000-000000000080',clock_timestamp()+interval '1 second','Synthetic expiry during lock'
from public.clinic_members m join public.clinics c on c.id=m.clinic_id
where c.name='Synthetic agenda A' and m.user_id='00000000-0000-0000-0000-000000000081';
select 1 from public.clinics where name='Synthetic agenda A' for update;
select pg_advisory_xact_lock(771136);
select pg_sleep(2);
commit;
SQL
publisher_pid=$!
ready=false
for attempt in {1..30};do
 available=$(docker exec "$container_name" psql -U postgres -Atc 'select pg_try_advisory_lock(771136)')
 if [ "$available" = f ];then ready=true;break;fi
 sleep 0.1
done
if [ "$ready" != true ];then wait "$publisher_pid";echo 'Expiry coordination failed';exit 1;fi
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expired.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic agenda A' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',false);
set role authenticated;
select public.ops_write(:'clinic','appointment','{"patient_name":"Synthetic blocked after expiry","species":"synthetic","kind":"consulta","professional_id":"00000000-0000-0000-0000-000000000082","starts_at":"2040-01-01T12:00:00Z","ends_at":"2040-01-01T13:00:00Z"}',repeat('1',48));
SQL
then echo 'ERROR: expired grant authorized waiting booking';exit 1;fi
wait "$publisher_pid" || { cat "$work_dir/expiry.log";exit 1; }
grep -Fq 'explicit_permission_required' "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if exists(select 1 from public.clinic_appointments where patient_name in ('Synthetic blocked after expiry','Synthetic blocked after revoke')) then raise exception 'unauthorized_concurrent_patient';end if;
end$$;
SQL
echo 'Agenda concurrency passed: committed revocation and expiry during lock deny booking.'
