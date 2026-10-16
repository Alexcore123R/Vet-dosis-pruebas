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
 echo 'Consultation concurrency coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000490',clinic_id,user_id,created_at,'prescription.prepare','00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day','Synthetic concurrency'
from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000170';
insert into public.prescriptions(id,clinic_id,case_id,patient_id,responsible_id,created_by)
select '00000000-0000-0000-0000-000000000491',clinic_id,id,patient_id,responsible_id,'00000000-0000-0000-0000-000000000152' from public.clinical_cases where title='Synthetic medication case';
SQL
cat > "$work_dir/sign.sql" <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);
set role authenticated;
select public.rx_consultation_sign('00000000-0000-0000-0000-000000000491',1,'Synthetic race signer','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('d5',24));
SQL
{ echo 'begin;';cat "$work_dir/sign.sql";echo 'select pg_advisory_xact_lock(771171);select pg_sleep(2);commit;'; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771171
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sign.sql" > "$work_dir/second.log" 2>&1 || { cat "$work_dir/second.log";exit 1; }
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/check.log" <<'SQL'
do $$begin
 if (select count(*) from private.prescription_consultation_attestations where prescription_id='00000000-0000-0000-0000-000000000491')<>1 then raise exception 'duplicate_consultation_signature';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke('00000000-0000-0000-0000-000000000490','Synthetic expiry test');
SQL
# Commit a short grant before the waiting statement starts. Expiry must be
# checked after the clinic lock, not just against statement_timestamp().
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/grant.log" <<'SQL'
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select m.clinic_id,m.user_id,m.created_at,'prescription.prepare','00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '2 seconds','Synthetic short grant'
from public.clinic_members m join public.clinics c on c.id=m.clinic_id where c.name='Synthetic medication permissions' and m.user_id='00000000-0000-0000-0000-000000000170';
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select id from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771172);select pg_sleep(3);commit;
SQL
first_pid=$!
wait_marker 771172
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sign.sql" > "$work_dir/expired.log" 2>&1;then echo 'Expired grant returned an old signature receipt';exit 1;fi
wait "$first_pid" || { cat "$work_dir/lock.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
echo 'Consultation concurrency passed: one signature; expired authority cannot reuse the receipt.'
