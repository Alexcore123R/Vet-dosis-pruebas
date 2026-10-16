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
 echo 'Resolution concurrency coordination failed'
 for trace in omit perform discharge revoke expiry;do if [ -f "$work_dir/$trace.log" ];then cat "$work_dir/$trace.log";fi;done
 exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as procedure from private.procedure_types where clinic_id=:'clinic' and name='Synthetic medication care' \gset
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000440',m.clinic_id,m.user_id,m.created_at,'medication.followup',:'procedure','00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day','Synthetic concurrency followup' from public.clinic_members m where m.clinic_id=:'clinic' and m.user_id='00000000-0000-0000-0000-000000000160';
insert into public.hospital_stays(id,clinic_id,patient_id,admitted_by) select '00000000-0000-0000-0000-000000000430',clinic_id,patient_id,'00000000-0000-0000-0000-000000000151' from public.clinical_cases where title='Synthetic medication case';
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,prescription_item_id,clinical_case_id,procedure_type_id,authority_grant_id)
select x.id,t.clinic_id,'00000000-0000-0000-0000-000000000430',t.kind,'Synthetic race','Synthetic',clock_timestamp()-interval '1 minute',15,t.created_by,t.prescription_item_id,t.clinical_case_id,t.procedure_type_id,t.authority_grant_id from public.hospital_tasks t
cross join (values('00000000-0000-0000-0000-000000000431'::uuid),('00000000-0000-0000-0000-000000000432'::uuid),('00000000-0000-0000-0000-000000000433'::uuid)) x(id) where t.id='00000000-0000-0000-0000-000000000400';
SQL
cat > "$work_dir/context.sql" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-permission-liquid' \gset
SQL
cat > "$work_dir/omit.sql" <<'SQL'
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',true);
set local role authenticated;
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000431',1,'not_given',null,'Synthetic first omission',repeat('d1',24));
select pg_advisory_xact_lock(771161);select pg_sleep(2);commit;
SQL
cat "$work_dir/context.sql" "$work_dir/omit.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/omit.log" 2>&1 &
first_pid=$!
wait_marker 771161
cat > "$work_dir/apply.sql" <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',false);
set role authenticated;
select public.rx_medication_report(:'case_id',jsonb_build_object('product_version_id',:'product','quantity','2','unit','ml','route','synthetic route','procedure','cuidados','performed_by',auth.uid(),'observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'vial_id','00000000-0000-0000-0000-000000000410','hospital_task_id',:'task','hospital_task_version',1),md5(:'task')||repeat('ab',8));
SQL
if { cat "$work_dir/context.sql"; echo "\set task '00000000-0000-0000-0000-000000000431'";cat "$work_dir/apply.sql"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/after_omit.log" 2>&1;then echo 'Application overwrote no-given';exit 1;fi
wait "$first_pid" || { cat "$work_dir/omit.log";exit 1; }
grep -Fq task_closed_without_application "$work_dir/after_omit.log" || { cat "$work_dir/after_omit.log";exit 1; }
# Reverse race: an application wins, so no omission can erase it.
{ cat "$work_dir/context.sql";echo "\set task '00000000-0000-0000-0000-000000000432'";echo 'begin;';cat "$work_dir/apply.sql";echo 'select pg_advisory_xact_lock(771162);select pg_sleep(2);commit;'; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/perform.log" 2>&1 &
first_pid=$!
wait_marker 771162
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/after_perform.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000432',1,'not_given',null,'Synthetic second omission',repeat('d3',24));
SQL
then echo 'Omission erased application';exit 1;fi
wait "$first_pid" || { cat "$work_dir/perform.log";exit 1; }
grep -Fq task_already_confirmed "$work_dir/after_perform.log" || { cat "$work_dir/after_perform.log";exit 1; }
# Discharge wins against a waiting application; it does not consume or refund volume.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/discharge.log" 2>&1 <<'SQL' &
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);set local role authenticated;
select public.hospital_discharge_preview(:'clinic','00000000-0000-0000-0000-000000000430') as preview \gset
select public.hospital_discharge_confirm(:'clinic','00000000-0000-0000-0000-000000000430',(:'preview'::jsonb->>'version')::int,:'preview'::jsonb->>'pending_hash','Synthetic concurrent discharge',repeat('d4',24));
select pg_advisory_xact_lock(771163);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771163
if { cat "$work_dir/context.sql";echo "\set task '00000000-0000-0000-0000-000000000433'";cat "$work_dir/apply.sql"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/after_discharge.log" 2>&1;then echo 'Application overwrote discharge';exit 1;fi
wait "$first_pid" || { cat "$work_dir/discharge.log";exit 1; }
grep -Fq task_closed_without_application "$work_dir/after_discharge.log" || { cat "$work_dir/after_discharge.log";exit 1; }
# Fresh authorization is required even to return a previously successful omission receipt.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',true);set local role authenticated;
select public.permission_revoke('00000000-0000-0000-0000-000000000440','Synthetic concurrent followup revocation');
select pg_advisory_xact_lock(771164);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771164
cat > "$work_dir/retry.sql" <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select public.hospital_medication_followup(:'clinic','00000000-0000-0000-0000-000000000431',1,'not_given',null,'Synthetic first omission',repeat('d1',24));
SQL
if cat "$work_dir/context.sql" "$work_dir/retry.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoked.log" 2>&1;then echo 'Revoked followup receipt returned';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/revoked.log" || { cat "$work_dir/revoked.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL' &
begin;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into private.member_permission_grants(clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
select m.clinic_id,m.user_id,m.created_at,'medication.followup',t.id,'00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 second','Synthetic followup expiry'
from public.clinic_members m join private.procedure_types t on t.clinic_id=m.clinic_id and t.name='Synthetic medication care' where m.clinic_id=:'clinic' and m.user_id='00000000-0000-0000-0000-000000000160';
select 1 from public.clinics where id=:'clinic' for update;
select pg_advisory_xact_lock(771165);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771165
if cat "$work_dir/context.sql" "$work_dir/retry.sql" | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expired.log" 2>&1;then echo 'Expired followup receipt returned';exit 1;fi
wait "$first_pid" || { cat "$work_dir/expiry.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expired.log" || { cat "$work_dir/expired.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if private.rx_vial_balance('00000000-0000-0000-0000-000000000410')<>6 then raise exception 'resolution_changed_physical_ledger';end if;
 if exists(select 1 from public.medication_records where hospital_task_id in ('00000000-0000-0000-0000-000000000431','00000000-0000-0000-0000-000000000433')) then raise exception 'application_after_resolution';end if;
 if (select count(*) from public.medication_records where hospital_task_id='00000000-0000-0000-0000-000000000432')<>1 then raise exception 'application_lost';end if;
 if (select count(*) from public.audit_log where action='hospital_medication_not_given' and entity_id='00000000-0000-0000-0000-000000000431')<>1 then raise exception 'duplicate_omission';end if;
end$$;
SQL
echo 'Resolution concurrency passed: first outcome wins, discharge/omission preserve volume, revocation and expiry deny retries.'
