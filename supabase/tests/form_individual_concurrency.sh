#!/usr/bin/env bash
set -euo pipefail
container_name=$1
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Two simultaneous confirmations of the exact reviewed PDF retain one issuance.
for attempt in 1 2;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/issue-$attempt.log" 2>&1 <<'SQL' &
select id as doc,revision,pdf_hash from public.form_documents where branding->>'header'='Synthetic individual flow' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_finalize(:'doc',:revision,:'pdf_hash');
create function pg_temp.assert_true(v boolean) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'Invalid signed document';end if;end$$;
select pg_temp.assert_true(public.form_read_pdf(:'doc')->>'hash'=:'pdf_hash');
select pg_temp.assert_true(not(public.form_document_snapshot(:'doc')->'snapshot' ? 'form_identity'));
SQL
 eval "issue_$attempt=$!"
done
for attempt in 1 2;do eval "pid=\$issue_$attempt";wait "$pid" || { cat "$work_dir/issue-$attempt.log";exit 1; };done
result=$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from private.form_flow_events where kind='issuance' and document_id=(select id from public.form_documents where branding->>'header'='Synthetic individual flow')")
[ "$result" = 1 ] || { echo 'Concurrent confirmations duplicated issuance';exit 1; }
# Simultaneous corrections of the same revision must have only one winner.
for attempt in 1 2; do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/correction-$attempt.log" 2>&1 <<SQL &
select id as doc from public.form_documents where version_id=(select id from public.form_template_versions where reason='Synthetic separately attributed clinical template') and state='draft' and created_by='00000000-0000-0000-0000-000000000170' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_reopen(:'doc',5,'00000000-0000-0000-0000-000000000151','Synthetic concurrent correction',repeat('193$attempt',12));
SQL
 eval "pid_$attempt=$!"
done
wins=0
for attempt in 1 2;do
 eval "pid=\$pid_$attempt"
 if wait "$pid";then wins=$((wins+1));else grep -Fq document_revision_conflict "$work_dir/correction-$attempt.log" || { cat "$work_dir/correction-$attempt.log";exit 1; };fi
done
[ "$wins" = 1 ] || { echo 'Concurrent corrections did not have exactly one winner';exit 1; }
echo 'Concurrent form correction: one winner, stale revision rejected.'

# Live expiry is checked after the clinic lock wait; stale reads do not authorize.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry-setup.log" 2>&1 <<'SQL' || { cat "$work_dir/expiry-setup.log";exit 1; }
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select private.permission_effective(:'clinic','00000000-0000-0000-0000-000000000170','form.prepare') as grant_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic expiry test');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000170','form.prepare',null,clock_timestamp()+interval '8 seconds','Synthetic short-lived preparer');
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/lock.log" 2>&1 <<'SQL' &
begin;
select 1 from public.clinics where name='Synthetic medication permissions' for update;
select pg_advisory_xact_lock(771516);select pg_sleep(10);commit;
SQL
locker=$!
ready=false
for attempt in {1..100};do
 if [ "$(docker exec "$container_name" psql -U postgres -Atc "select count(*) from pg_locks where locktype='advisory' and objid=771516 and granted")" = 1 ];then ready=true;break;fi
 sleep .1
done
[ "$ready" = true ] || { echo 'Lock marker unavailable';exit 1; }
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/expiry.log" 2>&1 <<'SQL'
select id as doc,revision from public.form_documents where version_id=(select id from public.form_template_versions where reason='Synthetic separately attributed clinical template') and state='draft' and created_by='00000000-0000-0000-0000-000000000170' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000170',false);set role authenticated;
select public.form_document_reopen(:'doc',:revision,'00000000-0000-0000-0000-000000000151','Synthetic expired correction',repeat('1933',12));
SQL
then echo 'Expired authority allowed correction';exit 1;fi
wait "$locker" || { cat "$work_dir/lock.log";exit 1; }
grep -Fq document_access_denied "$work_dir/expiry.log" || { cat "$work_dir/expiry.log";exit 1; }
echo 'Concurrent emission, correction and expiry after lock wait passed.'
