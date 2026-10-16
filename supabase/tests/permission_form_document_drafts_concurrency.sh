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
 echo 'Draft coordination failed';exit 1
}
cat > "$work_dir/sign.sql" <<'SQL'
select id as draft from public.form_documents where state='draft' and branding->>'header'='Synthetic changed header' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_authorship_sign(:'draft',2,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1821',12));
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sign.sql" > "$work_dir/a.log" 2>&1 &
first=$!
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sign.sql" > "$work_dir/b.log" 2>&1 &
second=$!
wait "$first" || { cat "$work_dir/a.log";exit 1; }
wait "$second" || { cat "$work_dir/b.log";exit 1; }
result=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from private.form_authorship_attestations where draft_revision=2 and document_id=(select id from public.form_documents where state='draft' and branding->>'header'='Synthetic changed header')")
[ "$result" = 1 ] || { echo 'Duplicate authorship signature';exit 1; }
# Current author authority is checked before returning an old operation receipt.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000170' and code='form.prepare' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic concurrent draft revocation');
select pg_advisory_xact_lock(771511);select pg_sleep(2);commit;
SQL
first=$!
wait_marker 771511
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/sign.sql" > "$work_dir/replay.log" 2>&1;then echo 'Revoked author replayed signature';exit 1;fi
wait "$first" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq document_access_denied "$work_dir/replay.log" || { cat "$work_dir/replay.log";exit 1; }
# A new short-lived grant applies only to a newly selected draft.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select patient_id as patient from public.clinical_cases where title='Synthetic medication case' \gset
select id as template from public.form_template_versions where reason='Synthetic reviewed template' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.prepare',null,clock_timestamp()+interval '8 seconds','Synthetic short author grant');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_draft_create(:'clinic',:'patient',:'template','00000000-0000-0000-0000-000000000151','{}','{"header":"Synthetic expiry waiting"}',repeat('1822',12));
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771512);select pg_sleep(10);commit;
SQL
first=$!
wait_marker 771512
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL'
select id as draft from public.form_documents where branding->>'header'='Synthetic expiry waiting' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_authorship_sign(:'draft',1,'Synthetic participant','[[0.1,0.2],[0.3,0.5],[0.7,0.6],null]',true,repeat('1823',12));
SQL
then echo 'Expired author signed document';exit 1;fi
wait "$first" || { cat "$work_dir/lock.log";exit 1; }
grep -Fq document_access_denied "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
result=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from private.form_authorship_attestations where document_id=(select id from public.form_documents where branding->>'header'='Synthetic expiry waiting')")
[ "$result" = 0 ] || { echo 'Expired author persisted signature';exit 1; }
echo 'Draft concurrent signature, live revocation and expiry after lock wait passed.'
