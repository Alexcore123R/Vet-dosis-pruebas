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
bash supabase/tests/terms_concurrency.sh "$container_name"
# Proposed privacy extension is tested locally, never applied by the remote operator.
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
update private.beta_policy set admissions_enabled=false,enforcement_enabled=false;
SQL
for sql_file in supabase/proposed/12C_privacy_binding.sql supabase/tests/privacy_binding.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/privacy.log" 2>&1 || { echo "FAILED: $sql_file";cat "$work_dir/privacy.log";exit 1; }
done
PYTHONPATH=scripts/supabase python3 - "$work_dir/privacy-draft.sql" <<'PYTEST'
from pathlib import Path
import sys
from privacy_schema import load_draft,load_privacy,binding_sql
Path(sys.argv[1]).write_text("begin;\nupdate private.beta_policy set admissions_enabled=false,enforcement_enabled=false;\n"+binding_sql(load_draft(),load_privacy())+"\ncommit;")
PYTEST
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$work_dir/privacy-draft.sql" > "$work_dir/privacy-draft.log" 2>&1 || { cat "$work_dir/privacy-draft.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if not exists(select 1 from private.beta_terms t join private.beta_privacy_notices n on n.version=t.privacy_version
 where t.version='1' and n.version='1' and not t.published and not n.published
 and t.content_hash=encode(sha256(convert_to(t.content,'UTF8')),'hex') and n.content_hash=encode(sha256(convert_to(n.content,'UTF8')),'hex')) then raise exception 'exact_privacy_draft_binding_failed';end if;
 if exists(select 1 from public.terms_acceptances where terms_version='1') then raise exception 'draft_implicitly_accepted';end if;
end$$;
SQL
for sql_file in supabase/proposed/12D_registration_legal_preview.sql supabase/tests/registration_legal_preview.sql;do
 docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql_file" > "$work_dir/registration-legal.log" 2>&1 || { echo "FAILED: $sql_file";cat "$work_dir/registration-legal.log";exit 1; }
done
echo 'Privacy passed: exact binding, legacy bypass rejected, historical rows preserved, own-user receipts, atomic enrollment and expired read/export.'
echo 'Terms passed: displayed version/hash bound to immutable acceptance, own-user history, stale text rejected, consent renewal without trial renewal, expired read/export preserved and guard reinstall safe.'
