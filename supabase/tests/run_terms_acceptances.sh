#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
container_name="vetdosis-terms-$$"
work_dir=$(mktemp -d)
docker run -d --name "$container_name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
trap 'docker rm -f "$container_name" >/dev/null; rm -rf "$work_dir"' EXIT
ready=false
for attempt in {1..30};do
 if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1;then ready=true;break;fi
 sleep 1
done
if [ "$ready" != true ];then echo 'PostgreSQL startup failed';exit 1;fi
for sql_file in supabase/tests/bootstrap.sql supabase/tests/existing_fixture.sql supabase/adaptations/existing_clinics_m2.sql supabase/adaptations/existing_patients_m4.sql supabase/adaptations/existing_hospital_m5.sql supabase/adaptations/existing_forms_phase1.sql supabase/adaptations/existing_forms_phase2.sql supabase/adaptations/existing_prescribing_m6.sql supabase/tests/storage_fixture.sql supabase/proposed/09A_beta_foundation.sql supabase/tests/terms_fixture.sql supabase/proposed/09B_beta_gate.sql supabase/proposed/11A_permission_foundation.sql supabase/proposed/12A_terms_acceptances.sql supabase/proposed/12B_platform_professional_admin.sql supabase/tests/terms_acceptances.sql supabase/tests/platform_professional.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/test.log" 2>&1 || { echo "FAILED: $sql_file";cat "$work_dir/test.log";exit 1; }
done
PYTHONPATH=scripts/supabase python3 - "$work_dir/draft.sql" <<'PYTEST'
from pathlib import Path
import sys
from legal_schema import load_draft,draft_sql
Path(sys.argv[1]).write_text("begin;\nset local standard_conforming_strings=on;\n"+draft_sql(load_draft())+"\ncommit;")
PYTEST
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/draft.sql" > "$work_dir/import.log" 2>&1 || { cat "$work_dir/import.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if not exists(select 1 from private.beta_terms where version='1' and not published and content_hash=encode(sha256(convert_to(content,'UTF8')),'hex')) then raise exception 'draft_source_hash_mismatch';end if;
 if exists(select 1 from public.terms_acceptances where terms_version='1') then raise exception 'draft_was_accepted';end if;
end$$;
SQL
echo 'Terms passed: displayed version/hash bound to immutable acceptance, own-user history, stale text rejected, consent renewal without trial renewal, expired read/export preserved and guard reinstall safe.'
