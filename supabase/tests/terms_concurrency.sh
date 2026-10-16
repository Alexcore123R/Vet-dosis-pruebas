#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# The same account may confirm twice concurrently; only one version row is appended.
for attempt in 1 2;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/accept-$attempt.log" 2>&1 <<'SQL' &
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.beta_accept_terms('test-2',encode(sha256(convert_to('Synthetic second terms','UTF8')),'hex'));
select pg_sleep(0.3);
commit;
SQL
 if [ "$attempt" = 1 ];then first_pid=$!;else second_pid=$!;fi
done
wait "$first_pid" || { cat "$work_dir/accept-1.log";exit 1; }
wait "$second_pid" || { cat "$work_dir/accept-2.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select count(*) from public.terms_acceptances where user_id='00000000-0000-0000-0000-000000000002' and terms_version='test-2')<>1 then raise exception 'duplicate_concurrent_acceptance';end if;
 if (select terms_version from private.beta_enrollments where user_id='00000000-0000-0000-0000-000000000002')<>'test-0' then raise exception 'concurrent_acceptance_changed_admission';end if;
end$$;
SQL
# Publisher starts first and holds its update uncommitted. Acceptance must wait,
# then validate the actual latest published version rather than a stale snapshot.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/publish.log" 2>&1 <<'SQL' &
begin;
insert into private.beta_terms(version,content,content_hash,published,published_at) values('test-3','Synthetic concurrent terms',encode(sha256(convert_to('Synthetic concurrent terms','UTF8')),'hex'),true,clock_timestamp());
select pg_advisory_xact_lock(778899);
select pg_sleep(3);
commit;
SQL
publisher_pid=$!
ready=false
for attempt in {1..20};do
 available=$(docker exec "$container_name" psql -U postgres -Atc 'select pg_try_advisory_lock(778899)')
 if [ "$available" = f ];then ready=true;break;fi
 sleep 0.1
done
if [ "$ready" != true ];then wait "$publisher_pid";echo 'Publisher coordination failed';exit 1;fi
if docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/stale.log" 2>&1 <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select public.beta_accept_terms('test-2',encode(sha256(convert_to('Synthetic second terms','UTF8')),'hex'));
SQL
then echo 'ERROR: stale concurrent version was accepted';exit 1;fi
wait "$publisher_pid" || { cat "$work_dir/publish.log";exit 1; }
grep -F 'beta_terms_changed' "$work_dir/stale.log" >/dev/null || { cat "$work_dir/stale.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if exists(select 1 from public.terms_acceptances where terms_version='test-3') then raise exception 'new_terms_accepted_without_confirmation';end if;
end$$;
SQL
echo 'Concurrent confirmations idempotent; publication race rejects stale text and never accepts a new version implicitly.'
