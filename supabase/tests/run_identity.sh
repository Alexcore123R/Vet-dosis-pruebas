#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-identity-$$"
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null' EXIT
ready=false
for attempt in $(seq 1 30);do
 if docker exec "$container_name" pg_isready -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'Postgres startup failed';exit 1;fi
for sql_file in supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_forms_phase1.sql supabase/tests/storage_fixture.sql supabase/proposed/10_identity.sql supabase/tests/identity_access.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file"
done
