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
 echo 'Prescription concurrency coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as case_id from public.clinical_cases where title='Synthetic medication case' \gset
select id as product from public.medication_product_versions where product_key='synthetic-prescription-workflow' \gset
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000530',clinic_id,user_id,created_at,'prescription.authorize','00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day','Synthetic concurrency'
from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000151';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.rx_create(:'case_id',jsonb_build_array(jsonb_build_object('product_version_id',:'product','quantity','1','unit','ml','route','Synthetic','interval','Synthetic','duration','Synthetic')),'','SYNTHETIC-RX-CONCURRENCY',repeat('f1',24))->>'id' as rx \gset
select public.rx_consultation_sign(:'rx',1,'Synthetic signer','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('f2',24)) as signature \gset
select public.rx_prepare_attributed(:'rx',1,:'signature','Synthetic signer');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_authorize_individual(:'rx',2,true);
select public.rx_pdf_snapshot('prescription',:'rx')->>'content_hash' as content_hash \gset
reset role;
set role service_role;
select public.rx_pdf_register('prescription',:'rx',3,:'content_hash',encode(convert_to('%PDF-SYNTHETIC-RACE','UTF8'),'base64'),'iVBORw0KGgo=');
SQL
cat > "$work_dir/confirm.sql" <<'SQL'
select id as rx,pdf_hash as hash from public.prescriptions where instructions='SYNTHETIC-RX-CONCURRENCY' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.rx_finalize(:'rx',3,:'hash');
SQL
{ echo 'begin;';cat "$work_dir/confirm.sql";echo 'select pg_advisory_xact_lock(771181);select pg_sleep(2);commit;'; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771181
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/second.log" 2>&1 || { cat "$work_dir/second.log";exit 1; }
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke('00000000-0000-0000-0000-000000000530','Synthetic concurrent authorization revocation');
select pg_advisory_xact_lock(771182);select pg_sleep(2);commit;
SQL
first_pid=$!
wait_marker 771182
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/confirm.sql" > "$work_dir/retry.log" 2>&1;then echo 'Revoked authority reused issuance receipt';exit 1;fi
wait "$first_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/retry.log" || { cat "$work_dir/retry.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/check.log" <<'SQL'
do $$declare recipe_id uuid;begin
 select r.id into recipe_id from public.prescriptions r where r.instructions='SYNTHETIC-RX-CONCURRENCY';
 if (select count(*) from public.audit_log where entity_id=recipe_id::text and action='prescription_issued')<>1 then raise exception 'issuance_not_exactly_once';end if;
end$$;
SQL
echo 'Prescription concurrency passed: one issuance; current authority checked before retry.'
