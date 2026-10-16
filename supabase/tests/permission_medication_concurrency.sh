#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
wait_marker(){
 local marker="$1"
 for attempt in {1..40};do
  if [ "$(docker exec "$container_name" psql -U postgres -Atc "select pg_try_advisory_lock($marker)")" = f ];then return;fi
  sleep 0.1
 done
 echo 'Medication concurrency coordination failed'
 for trace in first revoke expiry;do
  if [ -f "$work_dir/$trace.log" ];then cat "$work_dir/$trace.log";fi
 done
 exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000303',m.clinic_id,m.user_id,m.created_at,'vial.draw',t.id,'00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day','Synthetic concurrency draw'
from public.clinic_members m join private.procedure_types t on t.clinic_id=m.clinic_id and t.name='Synthetic medication care' where m.clinic_id=:'clinic' and m.user_id='00000000-0000-0000-0000-000000000152';
insert into public.medication_vials(id,clinic_id,product_version_id,lot,initial_volume,unit,responsible_id,opened_at)
select '00000000-0000-0000-0000-000000000302',:'clinic',id,'SYNTHETIC-CONCURRENT',10,'ml','00000000-0000-0000-0000-000000000151',clock_timestamp()-interval '1 minute' from public.medication_product_versions where product_key='synthetic-permission-liquid';
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,prescription_item_id,clinical_case_id,procedure_type_id,authority_grant_id)
select '00000000-0000-0000-0000-000000000300',clinic_id,stay_id,kind,'Synthetic concurrent medication','Synthetic',clock_timestamp()-interval '1 minute',15,created_by,prescription_item_id,clinical_case_id,procedure_type_id,authority_grant_id from public.hospital_tasks where clinic_id=:'clinic' limit 1;
SQL
# Each client builds the same task confirmation; operation keys differ.
cat > "$work_dir/application.sql" <<'SQL'
select id as case_id from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-permission-liquid' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
set role authenticated;
SQL
cat > "$work_dir/first.sql" <<'SQL'
begin;
select public.rx_medication_report(:'case_id',jsonb_build_object('product_version_id',:'product','quantity','2','unit','ml','route','synthetic route','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id','00000000-0000-0000-0000-000000000302','hospital_task_id','00000000-0000-0000-0000-000000000300'),repeat('a',48));
select pg_advisory_xact_lock(771151);
select pg_sleep(2);
commit;
SQL
cat "$work_dir/application.sql" "$work_dir/first.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771151
cat > "$work_dir/second.sql" <<'SQL'
select public.rx_medication_report(:'case_id',jsonb_build_object('product_version_id',:'product','quantity','2','unit','ml','route','synthetic route','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id','00000000-0000-0000-0000-000000000302','hospital_task_id','00000000-0000-0000-0000-000000000300'),repeat('b',48));
SQL
if cat "$work_dir/application.sql" "$work_dir/second.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/second.log" 2>&1;then echo 'Duplicate medication confirmation accepted';exit 1;fi
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
grep -Fq task_already_confirmed "$work_dir/second.log" || { cat "$work_dir/second.log";exit 1; }
# Revoke draw authority first: an administration grant alone cannot consume the vial.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',true);
set local role authenticated;
select public.permission_revoke('00000000-0000-0000-0000-000000000303','Synthetic concurrent draw revocation');
select pg_advisory_xact_lock(771152);
select pg_sleep(2);
commit;
SQL
first_pid=$!
wait_marker 771152
cat > "$work_dir/no_task.sql" <<'SQL'
select public.rx_medication_report(:'case_id',jsonb_build_object('product_version_id',:'product','quantity','2','unit','ml','route','synthetic route','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id','00000000-0000-0000-0000-000000000302'),repeat('c',48));
SQL
if cat "$work_dir/application.sql" "$work_dir/no_task.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoked.log" 2>&1;then echo 'Revoked draw consumed vial';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/revoked.log" || { cat "$work_dir/revoked.log";exit 1; }
# Expiry during lock wait must deny even if the statement began before expiry.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL' &
begin;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
select m.clinic_id,m.user_id,m.created_at,'vial.draw',t.id,'00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 second','Synthetic expiry'
from public.clinic_members m join private.procedure_types t on t.clinic_id=m.clinic_id and t.name='Synthetic medication care' where m.clinic_id=:'clinic' and m.user_id='00000000-0000-0000-0000-000000000152';
select 1 from public.clinics where id=:'clinic' for update;
select pg_advisory_xact_lock(771153);
select pg_sleep(2);
commit;
SQL
first_pid=$!
wait_marker 771153
if cat "$work_dir/application.sql" "$work_dir/no_task.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expired.log" 2>&1;then echo 'Expired draw consumed vial';exit 1;fi
wait "$first_pid" || { cat "$work_dir/expiry.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if private.rx_vial_balance('00000000-0000-0000-0000-000000000302')<>8 then raise exception 'duplicate_or_unauthorized_draw';end if;
 if (select count(*) from public.medication_records where hospital_task_id='00000000-0000-0000-0000-000000000300')<>1 then raise exception 'duplicate_medication_record';end if;
 if (select count(*) from public.medication_vial_movements where vial_id='00000000-0000-0000-0000-000000000302')<>1 then raise exception 'duplicate_ledger_movement';end if;
end$$;
SQL
echo 'Medication concurrency passed: one report and draw; revoked/expired draw cannot change balance.'
