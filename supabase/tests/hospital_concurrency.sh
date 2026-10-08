#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
test_logs=$(mktemp -d)
trap 'rm -rf "$test_logs"' EXIT
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$test_logs/setup" <<'SQL'
insert into auth.users values
('10000000-0000-0000-0000-000000000041','admin41@example.test',now()),
('10000000-0000-0000-0000-000000000042','aux42@example.test',now()),
('10000000-0000-0000-0000-000000000043','aux43@example.test',now());
insert into public.clinics(id,name,created_by) values('10000000-0000-0000-0000-000000000001','Concurrente ficticia','10000000-0000-0000-0000-000000000041');
insert into public.clinic_members(clinic_id,user_id,role) values
('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000041','admin'),
('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000042','auxiliar'),
('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000043','auxiliar');
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Ficticio','Ficticia','sin especificar','10000000-0000-0000-0000-000000000041');
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by) values('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','Box ficticio','10000000-0000-0000-0000-000000000041');
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by) values('10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','revision','Prueba concurrente','Sin uso clínico',now()-interval '1 minute',10,'10000000-0000-0000-0000-000000000041');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$test_logs/actor_a" 2>&1 <<'SQL' &
set application_name='m5-concurrency-A';
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000042',true);
select public.hospital_task_action('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004',1,'perform');
select pg_sleep(2);
commit;
SQL
actor_a_pid=$!
locked=false
for attempt in {1..20}; do
  if [ "$(docker exec "$container_name" psql -U postgres -tAc "select exists(select 1 from pg_stat_activity where application_name='m5-concurrency-A' and wait_event='PgSleep')")" = t ]; then
    locked=true
    break
  fi
  sleep 0.1
done
if [ "$locked" != true ]; then
  cat "$test_logs/actor_a"
  wait "$actor_a_pid"
  exit 1
fi
actor_b_status=0
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$test_logs/actor_b" 2>&1 <<'SQL' || actor_b_status=$?
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000043',true);
select public.hospital_task_action('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004',1,'perform');
commit;
SQL
wait "$actor_a_pid"
if [ "$actor_b_status" = 0 ] || ! rg -q 'task_not_pending' "$test_logs/actor_b"; then
  cat "$test_logs/actor_b"
  exit 1
fi
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if not exists(select 1 from public.hospital_tasks where id='10000000-0000-0000-0000-000000000004' and state='done' and version=2 and performed_by='10000000-0000-0000-0000-000000000042') then raise exception 'Concurrent administration corrupted';end if;
 if (select count(*) from public.audit_log where entity_id='10000000-0000-0000-0000-000000000004' and action='hospital_task_perform')<>1 then raise exception 'Concurrent audit duplicated';end if;
end $$;
select 'M5 simultaneous confirmations: one accepted, one blocked' as result;
SQL
