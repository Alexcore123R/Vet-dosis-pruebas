#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
wait_marker() {
 local marker="$1"
 for attempt in {1..40};do
  if [ "$(docker exec "$container_name" psql -U postgres -Atc "select pg_try_advisory_lock($marker)")" = f ];then return;fi
  sleep 0.1
 done
 echo 'Review concurrency coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id)
select x.id,c.id,s.id,'revision','Synthetic concurrent review','Synthetic',clock_timestamp()-interval '1 minute',15,'00000000-0000-0000-0000-000000000141',t.id,g.id
from public.clinics c join public.hospital_stays s on s.clinic_id=c.id
join private.procedure_types t on t.clinic_id=c.id and t.name='Synthetic review type'
join private.member_permission_grants g on g.clinic_id=c.id and g.code='hospital.schedule' and g.user_id='00000000-0000-0000-0000-000000000141'
cross join (values('00000000-0000-0000-0000-000000000200'::uuid),('00000000-0000-0000-0000-000000000201'::uuid)) x(id)
where c.name='Synthetic reviews clinic';
SQL
# The first server confirmation commits once; the second, including same actor, is notified.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 <<'SQL' &
select id as clinic from public.clinics where name='Synthetic reviews clinic' \gset
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
set local role authenticated;
select public.hospital_task_action(:'clinic','00000000-0000-0000-0000-000000000200',1,'perform');
select pg_advisory_xact_lock(771141);
select pg_sleep(2);
commit;
SQL
first_pid=$!
wait_marker 771141
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/second.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic reviews clinic' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select public.hospital_task_action(:'clinic','00000000-0000-0000-0000-000000000200',1,'perform');
SQL
then echo 'Duplicate confirmation accepted';exit 1;fi
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
grep -Fq task_already_confirmed "$work_dir/second.log" || { cat "$work_dir/second.log";exit 1; }
# Revocation commits before the waiting operation evaluates its authority.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000141' and code='procedure.perform' and procedure_id=(select id from private.procedure_types where name='Synthetic review type') \gset
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000140',true);
set local role authenticated;
select public.permission_revoke(:'grant_id','Synthetic concurrent review revocation');
select pg_advisory_xact_lock(771142);
select pg_sleep(2);
commit;
SQL
first_pid=$!
wait_marker 771142
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoked.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic reviews clinic' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select public.hospital_task_action(:'clinic','00000000-0000-0000-0000-000000000201',1,'perform');
SQL
then echo 'Revoked authority confirmed review';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/revoked.log" || { cat "$work_dir/revoked.log";exit 1; }
# Grant may expire during lock wait even though statement_timestamp precedes expiry.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expire.log" 2>&1 <<'SQL' &
begin;
select id as clinic from public.clinics where name='Synthetic reviews clinic' \gset
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
select m.clinic_id,m.user_id,m.created_at,'procedure.perform',t.id,'00000000-0000-0000-0000-000000000140',clock_timestamp()+interval '1 second','Synthetic expiry under lock'
from public.clinic_members m join private.procedure_types t on t.clinic_id=m.clinic_id and t.name='Synthetic review type'
where m.clinic_id=:'clinic' and m.user_id='00000000-0000-0000-0000-000000000141';
select 1 from public.clinics where id=:'clinic' for update;
select pg_advisory_xact_lock(771143);
select pg_sleep(2);
commit;
SQL
first_pid=$!
wait_marker 771143
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expired.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic reviews clinic' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',false);
set role authenticated;
select public.hospital_task_action(:'clinic','00000000-0000-0000-0000-000000000201',1,'perform');
SQL
then echo 'Expired authority confirmed review';exit 1;fi
wait "$first_pid" || { cat "$work_dir/expire.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if not exists(select 1 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000200' and state='done' and version=2) then raise exception 'first_confirmation_lost';end if;
 if (select count(*) from public.audit_log where entity_id='00000000-0000-0000-0000-000000000200' and action='hospital_task_perform')<>1 then raise exception 'duplicate_confirmation_audit';end if;
 if not exists(select 1 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000201' and state='pending' and version=1 and performed_by is null) then raise exception 'unauthorized_review';end if;
end$$;
SQL
echo 'Hospital review concurrency passed: first confirmation wins; revocation and expiry while waiting deny.'
