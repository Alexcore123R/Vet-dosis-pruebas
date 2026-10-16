#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Two edits from different explicitly permitted people race on the same version.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" 2>&1 <<'SQL' || { cat "$work_dir/setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.template.edit',null,clock_timestamp()+interval '1 day','Synthetic renewed editor');
SQL
cat > "$work_dir/edit.sql" <<'SQL'
select v.clinic_id as clinic,v.template_id as template,v.base_version_id as base,v.schema from public.form_template_versions v where v.reason='Synthetic later edit' \gset
set role authenticated;
select public.form_template_save(:'clinic',:'template',3,:'base',:'schema',false,'Synthetic concurrent edit',current_setting('test.operation'));
SQL
{ echo "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);select set_config('test.operation',repeat('1721',12),false);";cat "$work_dir/edit.sql"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/a.log" 2>&1 &
first=$!
{ echo "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);select set_config('test.operation',repeat('1722',12),false);";cat "$work_dir/edit.sql"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/b.log" 2>&1 &
second=$!
first_result=0;second_result=0
wait "$first" || first_result=$?
wait "$second" || second_result=$?
if [ "$first_result" = 0 ] && [ "$second_result" = 0 ];then echo 'Both stale edits succeeded';exit 1;fi
if [ "$first_result" != 0 ] && [ "$second_result" != 0 ];then cat "$work_dir/a.log" "$work_dir/b.log";exit 1;fi
if [ "$first_result" != 0 ];then grep -Fq template_version_conflict "$work_dir/a.log";else grep -Fq template_version_conflict "$work_dir/b.log";fi
echo 'Template concurrent version conflict passed.'
wait_marker(){
 for attempt in {1..40};do
  if [ "$(docker exec "$container_name" psql -U postgres -Atc "select pg_try_advisory_lock($1)")" = f ];then return;fi
  sleep 0.1
 done
 echo 'Template coordination failed';exit 1
}
# A pending receipt cannot restore editing after revocation has committed.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 <<'SQL' &
begin;
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000170' and code='form.template.edit' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic concurrent edit revocation');
select pg_advisory_xact_lock(771411);select pg_sleep(2);commit;
SQL
first=$!
wait_marker 771411
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/replay.log" 2>&1 <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as base,schema from public.form_template_versions where clinic_id is null and schema->>'type'='general' order by version desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_template_save(:'clinic',null,null,:'base',:'schema',false,'Synthetic pending template',repeat('1711',12));
SQL
then echo 'Revoked editor replayed receipt';exit 1;fi
wait "$first" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/replay.log" || { cat "$work_dir/replay.log";exit 1; }
# Approval expires while waiting on the shared clinic lock.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as grant_id from private.member_permission_grants where user_id='00000000-0000-0000-0000-000000000151' and code='form.template.approve' order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic renewal');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','form.template.approve',null,clock_timestamp()+interval '8 seconds','Synthetic short approval grant');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771412);select pg_sleep(10);commit;
SQL
first=$!
wait_marker 771412
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL'
select v.clinic_id as clinic,v.template_id as template,v.base_version_id as base,v.schema from public.form_template_versions v where v.reason='Synthetic concurrent edit' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.form_template_save(:'clinic',:'template',4,:'base',:'schema',true,'Synthetic expired approval',repeat('1723',12));
SQL
then echo 'Expired professional approval changed template';exit 1;fi
wait "$first" || { cat "$work_dir/lock.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
result=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from public.form_template_versions where reason='Synthetic expired approval'")
[ "$result" = 0 ] || { echo 'Expired approval was persisted';exit 1; }
echo 'Template revocation and real expiry after lock wait passed.'
