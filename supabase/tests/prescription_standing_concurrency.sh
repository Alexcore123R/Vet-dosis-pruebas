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
 echo 'Standing concurrency coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-prescription-workflow' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_standing_offer(:'case_id','00000000-0000-0000-0000-000000000170',to_char((clock_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true,repeat('1371',12)) as delegation \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_standing_accept(:'delegation',true,repeat('1372',12));
select public.rx_create(:'case_id',jsonb_build_array(jsonb_build_object('product_version_id',:'product','quantity','1','unit','ml','route','Synthetic','interval','Synthetic','duration','Synthetic')),'','SYNTHETIC-STANDING-CONCURRENCY',repeat('1373',12))->>'id' as rx \gset
select public.rx_consultation_sign(:'rx',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1374',12)) as signature \gset
select public.rx_prepare_standing(:'rx',1,:'signature','Synthetic participant',:'delegation');
select public.rx_pdf_snapshot('prescription',:'rx')->>'content_hash' as content_hash \gset
reset role;
set role service_role;
select public.rx_pdf_register('prescription',:'rx',2,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-STANDING-RACE','UTF8'),'base64'),'iVBORw0KGgo=');
SQL
cat > "$work_dir/confirm.sql" <<'SQL'
select id as rx,pdf_hash as hash from public.prescriptions where instructions='SYNTHETIC-STANDING-CONCURRENCY' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_finalize(:'rx',2,:'hash');
SQL
{ echo 'begin;';cat "$work_dir/confirm.sql";echo 'select pg_advisory_xact_lock(771191);select pg_sleep(2);commit;'; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771191
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/second.log" 2>&1 || { cat "$work_dir/second.log";exit 1; }
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_standing_resume(:'clinic','Synthetic concurrent return',repeat('1375',12));
select pg_advisory_xact_lock(771192);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771192
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/retry.log" 2>&1;then echo 'Revoked standing authorization reused issuance receipt';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq standing_authorization_unavailable "$work_dir/retry.log" || { cat "$work_dir/retry.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/check.log" <<'SQL'
do $$declare recipe_id uuid;begin
 select r.id into recipe_id from public.prescriptions r where r.instructions='SYNTHETIC-STANDING-CONCURRENCY';
 if (select count(*) from public.audit_log where entity_id=recipe_id::text and action='prescription_issued')<>1 then raise exception 'issuance_not_exactly_once';end if;
 if (select count(*) from private.rx_standing_events where prescription_id=recipe_id)<>1 then raise exception 'inbox_not_exactly_once';end if;
end$$;
SQL
echo 'Standing concurrency passed: one issuance/inbox event; revocation wins before retry.'
# The final statement starts while valid, then waits behind the clinic lock.
# clock_timestamp() must reject it after expiry, not reuse statement_timestamp().
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-prescription-workflow' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_standing_offer(:'case_id','00000000-0000-0000-0000-000000000170',to_char((clock_timestamp()+interval '8 seconds') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true,repeat('1376',12)) as delegation \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_standing_accept(:'delegation',true,repeat('1377',12));
select public.rx_create(:'case_id',jsonb_build_array(jsonb_build_object('product_version_id',:'product','quantity','1','unit','ml','route','Synthetic','interval','Synthetic','duration','Synthetic')),'','SYNTHETIC-STANDING-EXPIRY',repeat('1378',12))->>'id' as rx \gset
select public.rx_consultation_sign(:'rx',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1379',12)) as signature \gset
select public.rx_prepare_standing(:'rx',1,:'signature','Synthetic participant',:'delegation');
select public.rx_pdf_snapshot('prescription',:'rx')->>'content_hash' as content_hash \gset
reset role;
set role service_role;
select public.rx_pdf_register('prescription',:'rx',2,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-EXPIRY','UTF8'),'base64'),'iVBORw0KGgo=');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771193);select pg_sleep(10);commit;
SQL
first_pid=$!
wait_marker 771193
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL'
select id as rx,pdf_hash as hash,delegation_id as delegation from public.prescriptions where instructions='SYNTHETIC-STANDING-EXPIRY' \gset
select 1/(case when valid_until>clock_timestamp()+interval '1 second' then 1 else 0 end) from public.professional_delegations where id=:'delegation';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_finalize(:'rx',2,:'hash');
SQL
then echo 'Standing expiry during lock wait accepted';exit 1;fi
wait "$first_pid" || { cat "$work_dir/expiry-lock.log";exit 1; }
grep -Fq standing_authorization_unavailable "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if not exists(select 1 from public.prescriptions where instructions='SYNTHETIC-STANDING-EXPIRY' and state='ready') then raise exception 'expired_document_changed';end if;
 if exists(select 1 from private.rx_standing_events e join public.prescriptions r on r.id=e.prescription_id where r.instructions='SYNTHETIC-STANDING-EXPIRY') then raise exception 'expired_document_notified_as_issued';end if;
end$$;
SQL
echo 'Standing expiry after lock wait passed: no issuance or inbox event.'
