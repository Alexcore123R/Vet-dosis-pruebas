#!/usr/bin/env bash
# Two real PostgreSQL sessions; fake credentials and messages only.
# The database/container is disposable and never connects to Supabase remotely.
set -euo pipefail
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <postgres-docker-container>" >&2
  exit 2
fi
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/setup.sql" <<'SQL'
\set ON_ERROR_STOP on
begin;
insert into public.ai_connections(id,provider,scope,owner_id,created_by)
values('c8000000-0000-4000-8000-000000000017','openai','personal',
       '00000000-0000-0000-0000-000000000111',
       '00000000-0000-0000-0000-000000000111');
insert into private.ai_credentials(connection_id,ciphertext,nonce)
values('c8000000-0000-4000-8000-000000000017',
       'synthetic-ciphertext-race-001','synthetic-nonce-race-001');
insert into public.ai_chats(id,clinic_id,owner_id,title)
select 'c8000000-0000-4000-8000-000000000018',id,
       '00000000-0000-0000-0000-000000000111','Synthetic concurrent rotation'
from public.clinics where name='Synthetic clinical permission A';
insert into public.ai_messages(id,clinic_id,chat_id,role,body,created_by)
select 'c8000000-0000-4000-8000-000000000019',clinic_id,
       'c8000000-0000-4000-8000-000000000018','user',
       'synthetic in-flight message','00000000-0000-0000-0000-000000000111'
from public.ai_chats where id='c8000000-0000-4000-8000-000000000018';
insert into public.ai_requests(id,clinic_id,chat_id,user_id,connection_id,
                               model,operation,personal_context,team_context,input_message_id)
select 'c8000000-0000-4000-8000-000000000020',clinic_id,id,
       '00000000-0000-0000-0000-000000000111',
       'c8000000-0000-4000-8000-000000000017','synthetic-model',
       'synthetic-concurrent-rotation-operation-001',false,false,
       'c8000000-0000-4000-8000-000000000019'
from public.ai_chats where id='c8000000-0000-4000-8000-000000000018';
update public.ai_requests set state='processing'
where id='c8000000-0000-4000-8000-000000000020';
do $$
begin
  if (select credential_version from public.ai_requests
      where id='c8000000-0000-4000-8000-000000000020') is distinct from 1 then
    raise exception 'the in-flight request did not capture key version 1';
  end if;
end$$;
commit;
SQL
if ! docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 \
  < "$work_dir/setup.sql" > "$work_dir/setup.log" 2>&1; then
  cat "$work_dir/setup.log"
  exit 1
fi

cat > "$work_dir/rotate.sql" <<'SQL'
\set ON_ERROR_STOP on
begin;
select public.ai_key_rotate_server(
  '00000000-0000-0000-0000-000000000111',
  'c8000000-0000-4000-8000-000000000017',
  'synthetic-ciphertext-race-002','synthetic-nonce-race-002'
);
\echo ROTATION_UNCOMMITTED
-- Keep the row-update lock through a competing finish attempt.
select pg_sleep(5);
commit;
SQL
cat > "$work_dir/finish.sql" <<'SQL'
\set ON_ERROR_STOP on
set statement_timeout = '15s';
select public.ai_finish_server(
  'c8000000-0000-4000-8000-000000000020',
  '00000000-0000-0000-0000-000000000111',
  'stale synthetic answer must not be saved',true
);
do $$
begin
  if (select state from public.ai_requests
      where id='c8000000-0000-4000-8000-000000000020') <> 'failed' then
    raise exception 'stale concurrent completion was accepted';
  end if;
  if exists(select 1 from public.ai_messages
            where chat_id='c8000000-0000-4000-8000-000000000018'
              and role='assistant') then
    raise exception 'stale concurrent answer was committed';
  end if;
  if (select key_version from private.ai_credentials
      where connection_id='c8000000-0000-4000-8000-000000000017') <> 2 then
    raise exception 'rotation did not commit exactly once';
  end if;
end$$;
SQL

docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 \
  < "$work_dir/rotate.sql" > "$work_dir/rotate.log" 2>&1 &
rotate_pid=$!
ready=false
for attempt in $(seq 1 100); do
  if grep -q 'ROTATION_UNCOMMITTED' "$work_dir/rotate.log"; then
    ready=true
    break
  fi
  if ! kill -0 "$rotate_pid" 2>/dev/null; then break; fi
  sleep 0.05
done
if [ "$ready" != true ]; then
  cat "$work_dir/rotate.log"
  wait "$rotate_pid" || true
  echo 'Rotation transaction did not reach the synchronization point' >&2
  exit 1
fi

docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 \
  < "$work_dir/finish.sql" > "$work_dir/finish.log" 2>&1 &
finish_pid=$!
blocked=false
for attempt in $(seq 1 65); do
  waiting=$(docker exec "$container_name" psql -U postgres -Atqc \
    "select exists(select 1 from pg_stat_activity where wait_event_type='Lock' and query like 'select public.ai_finish_server(%');")
  if [ "$waiting" = t ]; then
    blocked=true
    break
  fi
  if ! kill -0 "$finish_pid" 2>/dev/null; then break; fi
  sleep 0.05
done

if ! wait "$rotate_pid"; then
  cat "$work_dir/rotate.log"
  exit 1
fi
if ! wait "$finish_pid"; then
  cat "$work_dir/finish.log"
  exit 1
fi
if [ "$blocked" != true ]; then
  echo 'The competing finish never demonstrably waited on the credential lock' >&2
  cat "$work_dir/rotate.log"
  cat "$work_dir/finish.log"
  exit 1
fi
echo 'Concurrent credential rotation rejected a stale in-flight answer.'
