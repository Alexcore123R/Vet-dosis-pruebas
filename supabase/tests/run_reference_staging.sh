#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-reference-staging-$$"
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null' EXIT
ready=false
for attempt in {1..30}; do
  if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
if [ "$ready" != true ]; then echo 'PostgreSQL startup failed'; exit 1; fi
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < supabase/proposed/15A_reference_staging.sql
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < supabase/proposed/15A_reference_staging.sql
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/reference_staging.sql
echo 'Isolated reference staging passed; no remote connection was used.'
