#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-dashboard-metrics-$$"
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust -v "$PWD:/work:ro" -w /work postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null' EXIT
for attempt in {1..30}; do
 if docker exec "$container_name" pg_isready -U postgres >/dev/null 2>&1; then break; fi
 sleep 1
done
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/dashboard_sales_metrics.sql
