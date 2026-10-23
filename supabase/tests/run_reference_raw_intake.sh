#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-raw-intake-$$"
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null' EXIT
ready=false
for attempt in {1..30}; do
  if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
  sleep 1
done
if [ "$ready" != true ];then echo 'PostgreSQL startup failed';exit 1;fi
for sql_file in supabase/proposed/15A_reference_staging.sql supabase/proposed/15B_reference_raw_intake.sql supabase/tests/reference_raw_intake.sql;do
  docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" ||
    { echo "FAILED: $sql_file";exit 1; }
done
echo 'Synthetic private raw intake check passed in isolated PostgreSQL.'
